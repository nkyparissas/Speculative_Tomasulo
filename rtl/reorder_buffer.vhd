-- Speculative Tomasulo processor
-- Vibecoded by Nick Kyparissas using Claude Opus 5.5, based on the original
-- Speculative Tomasulo project (see README.md).
--
-- REORDER_BUFFER: in-order commit, operand lookup and exception recovery.
--
-- The reorder buffer (ROB) is a circular buffer of ROB_SIZE entries that
-- holds every issued instruction until it commits in program order. Issue
-- allocates the entry at the tail, commit releases the entry at the head, and
-- the index of an entry serves as the tag under which the result of its
-- instruction is broadcast. Results thus remain speculative in the ROB until
-- they commit, which allows an exception to discard younger instructions
-- without corrupting the architectural register file. A busy bit marks the
-- entries that hold an instruction; in particular, the buffer is full when
-- the entry at the tail is busy.
--
-- In every cycle, the clocked process performs six steps in a fixed order,
-- and a later step overrides an earlier one where both assign the same
-- signal. (1) Recovery: in the cycle after an exception, the tail returns to
-- the faulting entry and the flush notification ends. (2) Writeback: the
-- busy entry named by the CDB tag stores the broadcast value and is marked
-- done. A result for an entry that is not busy belongs to an instruction
-- that an exception has just discarded, and it is ignored. (3) Commit: if the
-- head entry is done, or receives its result from the CDB in this very
-- cycle, its value goes to the register file through the registered commit
-- port, the entry is released and the head advances. (4) Allocation: an
-- issued instruction occupies the tail entry, and the tail advances.
-- (5) Exception, described below. (6) Lookup: for each source register of
-- the instruction presented at the issue stage, the ROB reports the youngest
-- busy entry that writes the register, or TAG_NONE if the register file is
-- up to date, and a producer whose result the CDB broadcasts in this cycle
-- supplies its value from the bus. These registered results reach the
-- reservation stations one cycle after issue, together with the register
-- file's data.
--
-- Exceptions are signalled from outside, with exception_flag and the tag of
-- the faulting instruction. The ROB accepts an exception only if the tag
-- names a busy entry, and it ignores a request for any other tag, such as
-- that of an instruction that has already committed or been discarded. In
-- the cycle of an accepted exception, no entry commits, since the faulting
-- entry may be the head. Instead, step (5) discards the faulting entry and
-- all younger ones, including an instruction allocated in step (4), reports
-- the program counter of the faulting instruction and publishes its tag on
-- flush_tag. In the following cycle, the reservation stations and the
-- functional units discard the same range, from flush_tag up to rob_tail,
-- and the fetch unit, which also observes flush_tag, moves to the exception
-- handler.
--
-- Names:
--   pc, issue, instruction  instruction at the issue stage, and whether it issues
--   rob_tail, rob_full      tag of the next free entry, and whether it is busy
--   rs_*, rt_*              lookup results for the source registers of that instruction
--   cdb_tag, cdb_value      result broadcast on the common data bus
--   commit_*                registered write port of the register file
--   exception_flag/_tag     exception request and the faulting entry
--   exception_pc            program counter of the most recent faulting instruction
--   flush_tag               first discarded entry during the cycle after an
--                           exception, TAG_NONE otherwise
--   entries, head, tail     buffer contents and circular pointers

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tomasulo_pkg.all;

entity reorder_buffer is
    port (
        clk            : in  std_logic;
        rst            : in  std_logic;
        -- Issue
        pc             : in  pc_t;
        issue          : in  std_logic;
        instruction    : in  instr_t;
        rob_tail       : out tag_t;
        rob_full       : out std_logic;
        -- Operand lookup, one cycle after issue
        rs_tag         : out tag_t;
        rt_tag         : out tag_t;
        rs_value       : out word_t;
        rt_value       : out word_t;
        rs_valid       : out std_logic;
        rt_valid       : out std_logic;
        -- Common data bus
        cdb_tag        : in  tag_t;
        cdb_value      : in  word_t;
        -- Commit to the register file
        commit_we      : out std_logic;
        commit_rd      : out reg_addr_t;
        commit_value   : out word_t;
        -- Exceptions
        exception_flag : in  std_logic;
        exception_tag  : in  tag_t;
        exception_pc   : out pc_t;
        flush_tag      : out tag_t);
end reorder_buffer;

architecture rtl of reorder_buffer is

    type entry_array_t is array (0 to ROB_SIZE - 1) of rob_entry_t;

    function next_index(i : natural) return natural is
    begin
        if i = ROB_SIZE - 1 then
            return 0;
        else
            return i + 1;
        end if;
    end function next_index;

    function to_tag(i : natural) return tag_t is
    begin
        return std_logic_vector(to_unsigned(i, tag_t'length));
    end function to_tag;

    signal entries       : entry_array_t := (others => ROB_ENTRY_EMPTY);
    signal head          : natural range 0 to ROB_SIZE - 1 := 0;
    signal tail          : natural range 0 to ROB_SIZE - 1 := 0;
    signal flush_tag_reg : tag_t := TAG_NONE;

    -- True if the tag names a busy entry; false for TAG_NONE.
    impure function busy(tag : tag_t) return boolean is
    begin
        return tag /= TAG_NONE and entries(to_integer(unsigned(tag))).busy = '1';
    end function busy;

begin

    process
        variable accepted : boolean;
        variable new_tail : natural range 0 to ROB_SIZE - 1;
        variable i        : natural range 0 to ROB_SIZE - 1;
        -- Producers of rs and rt found by the lookup of step (6).
        variable rs_found, rt_found : boolean;
        variable rs_entry, rt_entry : natural range 0 to ROB_SIZE - 1;
    begin
        wait until rising_edge(clk);
        accepted := exception_flag = '1' and busy(exception_tag);

        if rst = '1' then
            entries       <= (others => ROB_ENTRY_EMPTY);
            head          <= 0;
            tail          <= 0;
            flush_tag_reg <= TAG_NONE;
            exception_pc  <= (others => '0');
            commit_we     <= '0';
            commit_rd     <= (others => '0');
            commit_value  <= (others => '0');
            rs_tag        <= TAG_NONE;
            rt_tag        <= TAG_NONE;
            rs_value      <= (others => '0');
            rt_value      <= (others => '0');
            rs_valid      <= '0';
            rt_valid      <= '0';

        else
            -- (1) Recovery.
            if flush_tag_reg /= TAG_NONE then
                tail          <= to_integer(unsigned(flush_tag_reg));
                flush_tag_reg <= TAG_NONE;
            end if;

            -- (2) Writeback.
            if busy(cdb_tag) then
                entries(to_integer(unsigned(cdb_tag))).value <= cdb_value;
                entries(to_integer(unsigned(cdb_tag))).done  <= '1';
            end if;

            -- (3) Commit, either from the head entry or directly from the CDB
            -- when the head's result is being broadcast in this cycle.
            commit_we <= '0';
            if not accepted and entries(head).busy = '1'
               and (entries(head).done = '1' or cdb_tag = to_tag(head)) then
                commit_we <= '1';
                commit_rd <= entries(head).rd;
                if entries(head).done = '1' then
                    commit_value <= entries(head).value;
                else
                    commit_value <= cdb_value;
                end if;
                entries(head) <= ROB_ENTRY_EMPTY;
                head          <= next_index(head);
            end if;

            -- (4) Allocation. The reservation stations accept no instruction
            -- while the buffer is full, so the tail entry is free whenever
            -- issue = '1'.
            new_tail := tail;
            if issue = '1' then
                entries(tail) <= (busy  => '1',
                                  pc    => pc,
                                  rd    => instruction(RD_FIELD),
                                  value => (others => '0'),
                                  done  => '0');
                new_tail := next_index(tail);
                tail     <= new_tail;
            end if;

            -- (5) Exception: discard the entries from the faulting one up to
            -- the new tail.
            if accepted then
                for e in entries'range loop
                    if in_flush_range(to_tag(e), exception_tag, to_tag(new_tail)) then
                        entries(e) <= ROB_ENTRY_EMPTY;
                    end if;
                end loop;
                flush_tag_reg <= exception_tag;
                exception_pc  <= entries(to_integer(unsigned(exception_tag))).pc;
            end if;

            -- (6) Lookup. The search visits the busy entries from the oldest
            -- to the youngest, so the youngest producer is recorded last.
            rs_found := false;
            rt_found := false;
            i := head;
            for age in 0 to ROB_SIZE - 1 loop
                if entries(i).busy = '1' then
                    if entries(i).rd = instruction(RS_FIELD) then
                        rs_found := true;
                        rs_entry := i;
                    end if;
                    if entries(i).rd = instruction(RT_FIELD) then
                        rt_found := true;
                        rt_entry := i;
                    end if;
                end if;
                i := next_index(i);
            end loop;

            -- The value outputs keep their previous contents when no producer
            -- is found, since only the tags signal a match.
            rs_tag   <= TAG_NONE;
            rt_tag   <= TAG_NONE;
            rs_valid <= '0';
            rt_valid <= '0';
            if rs_found then
                rs_tag <= to_tag(rs_entry);
                if cdb_tag = to_tag(rs_entry) then
                    rs_value <= cdb_value;
                    rs_valid <= '1';
                else
                    rs_value <= entries(rs_entry).value;
                    rs_valid <= entries(rs_entry).done;
                end if;
            end if;
            if rt_found then
                rt_tag <= to_tag(rt_entry);
                if cdb_tag = to_tag(rt_entry) then
                    rt_value <= cdb_value;
                    rt_valid <= '1';
                else
                    rt_value <= entries(rt_entry).value;
                    rt_valid <= entries(rt_entry).done;
                end if;
            end if;
        end if;
    end process;

    rob_tail  <= to_tag(tail);
    rob_full  <= entries(tail).busy;
    flush_tag <= flush_tag_reg;

end rtl;
