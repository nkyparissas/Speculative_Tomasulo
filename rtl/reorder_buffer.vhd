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
-- without corrupting the architectural register file.
--
-- In every cycle without an exception, the clocked process performs five
-- steps in a fixed order, and a later step overrides an earlier one where
-- both assign the same signal. (1) Recovery: in the cycle after an
-- exception, the tail returns to the faulting entry and the flush
-- notification ends. (2) Writeback: the entry named by the CDB tag stores the
-- broadcast value and is marked done. (3) Commit: if the head entry is done,
-- or receives its result from the CDB in this very cycle, its value goes to
-- the register file through the registered commit port, the entry is
-- released and the head advances. (4) Allocation: an issued instruction
-- occupies the tail entry, and the tail advances. (5) Lookup: for each source
-- register of the instruction presented at the issue stage, the ROB reports
-- the youngest in-flight entry that writes the register, or TAG_NONE if the
-- register file is up to date. The search only considers the entries between
-- head and tail, and a producer whose result the CDB broadcasts in this cycle
-- supplies its value from the bus. The registered results reach the
-- reservation stations one cycle after issue, together with the register
-- file's data.
--
-- Exceptions are signalled from outside, with exception_flag and the tag of
-- the faulting instruction. In that cycle, the ROB discards the faulting
-- entry and all younger ones, reports the program counter of the faulting
-- instruction and publishes its tag on flush_tag, so that the reservation
-- stations discard the same instructions in the following cycle. The ROB
-- performs none of the regular steps in the exception cycle
-- (doc/known_issues.md, KI-1), and the fetch unit is not redirected (KI-10).
--
-- Names:
--   pc, issue, instruction  instruction at the issue stage, and whether it issues
--   rob_tail                tag of the next free entry, i.e. of the next instruction
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

    type entry_array_t is array (ROB_SIZE - 1 downto 0) of rob_entry_t;

    subtype pointer_t is unsigned(tag_t'range);

    function next_pointer(p : pointer_t) return pointer_t is
    begin
        if p = ROB_SIZE - 1 then
            return (others => '0');
        else
            return p + 1;
        end if;
    end function next_pointer;

    -- True if entry i belongs to the discarded range, which starts at the
    -- faulting entry and ends at tail - 1. Note that tail - 1 is computed
    -- modulo 16, so a tail of 0 extends the range to every entry (KI-8).
    function flushed(i : natural; first : tag_t; tail : pointer_t) return boolean is
        constant last : natural := to_integer(tail - 1);
    begin
        if unsigned(first) <= tail then
            return i >= to_integer(unsigned(first)) and i <= last;
        else
            return i >= to_integer(unsigned(first)) or i <= last;
        end if;
    end function flushed;

    signal entries       : entry_array_t := (others => ROB_ENTRY_EMPTY);
    signal head          : pointer_t     := (others => '0');
    signal tail          : pointer_t     := (others => '0');
    signal flush_tag_reg : tag_t         := TAG_NONE;

begin

    process
        -- Producers of rs and rt found by the lookup of step (5).
        variable rs_found, rt_found : boolean;
        variable rs_entry, rt_entry : natural range 0 to ROB_SIZE - 1;

        -- Records entry i as the producer of rs and/or rt if it writes one of
        -- them. The searches below call it from the oldest to the youngest
        -- entry, so the youngest producer is recorded.
        procedure match(i : natural) is
        begin
            if entries(i).rd = instruction(RS_FIELD) then
                rs_found := true;
                rs_entry := i;
            end if;
            if entries(i).rd = instruction(RT_FIELD) then
                rt_found := true;
                rt_entry := i;
            end if;
        end procedure match;
    begin
        wait until rising_edge(clk);
        if rst = '1' then
            commit_we     <= '0';
            commit_rd     <= (others => '0');
            commit_value  <= (others => '0');
            rs_tag        <= TAG_NONE;
            rt_tag        <= TAG_NONE;
            rs_value      <= (others => '0');
            rt_value      <= (others => '0');
            rs_valid      <= '0';
            rt_valid      <= '0';
            exception_pc  <= (others => '0');
            flush_tag_reg <= TAG_NONE;
            head          <= (others => '0');
            tail          <= (others => '0');
            entries       <= (others => ROB_ENTRY_EMPTY);

        elsif exception_flag = '1' then
            -- The commit port and the lookup results keep their values, so a
            -- commit registered in the previous cycle is written twice (KI-11).
            exception_pc  <= entries(to_integer(unsigned(exception_tag))).pc;
            flush_tag_reg <= exception_tag;
            for i in 0 to ROB_SIZE - 1 loop
                if flushed(i, exception_tag, tail) then
                    entries(i) <= ROB_ENTRY_EMPTY;
                end if;
            end loop;

        else
            -- (1) Recovery. The tail is taken from the input port again rather
            -- than from flush_tag_reg (KI-9).
            if flush_tag_reg /= TAG_NONE then
                tail          <= unsigned(exception_tag);
                flush_tag_reg <= TAG_NONE;
            end if;

            -- (2) Writeback.
            if cdb_tag /= TAG_NONE then
                entries(to_integer(unsigned(cdb_tag))).value <= cdb_value;
                entries(to_integer(unsigned(cdb_tag))).done  <= '1';
            end if;

            -- (3) Commit, either from the head entry or directly from the CDB
            -- when the head's result is being broadcast in this cycle.
            if entries(to_integer(head)).done = '1' then
                commit_we                 <= '1';
                commit_rd                 <= entries(to_integer(head)).rd;
                commit_value              <= entries(to_integer(head)).value;
                entries(to_integer(head)) <= ROB_ENTRY_EMPTY;
                head                      <= next_pointer(head);
            elsif unsigned(cdb_tag) = head then
                commit_we                 <= '1';
                commit_rd                 <= entries(to_integer(head)).rd;
                commit_value              <= cdb_value;
                entries(to_integer(head)) <= ROB_ENTRY_EMPTY;
                head                      <= next_pointer(head);
            else
                commit_we <= '0';
            end if;

            -- (4) Allocation, without checking for a free entry (KI-5). The
            -- value field keeps its contents, which are zero unless a stale
            -- result was written into the released entry (KI-6).
            if issue = '1' then
                entries(to_integer(tail)).opcode <= instruction(OPCODE_FIELD);
                entries(to_integer(tail)).pc     <= pc;
                entries(to_integer(tail)).rd     <= instruction(RD_FIELD);
                entries(to_integer(tail)).done   <= '0';
                tail <= next_pointer(tail);
            end if;

            -- (5) Lookup of the youngest in-flight producer of each source
            -- register.
            rs_found := false;
            rt_found := false;
            if head < tail then
                for i in 0 to ROB_SIZE - 1 loop
                    if i >= to_integer(head) and i < to_integer(tail) then
                        match(i);
                    end if;
                end loop;
            elsif head /= tail then
                -- The occupied entries wrap around: search from the head to
                -- the end of the buffer, then from the start up to the entry
                -- before the tail. The bound is compared as an integer, so a
                -- tail of 0 leaves the second loop empty instead of wrapping
                -- to 15 in 4-bit arithmetic.
                for i in 0 to ROB_SIZE - 1 loop
                    if i >= to_integer(head) then
                        match(i);
                    end if;
                end loop;
                for i in 0 to ROB_SIZE - 1 loop
                    if i < to_integer(tail) then
                        match(i);
                    end if;
                end loop;
            end if;

            -- A producer whose result the CDB broadcasts in this cycle is not
            -- marked done before the next edge, so its value comes from the
            -- bus. The value outputs keep their previous contents when no
            -- producer is found, since only the tags signal a match.
            rs_tag   <= TAG_NONE;
            rt_tag   <= TAG_NONE;
            rs_valid <= '0';
            rt_valid <= '0';
            if rs_found then
                rs_tag <= std_logic_vector(to_unsigned(rs_entry, tag_t'length));
                if unsigned(cdb_tag) = rs_entry then
                    rs_value <= cdb_value;
                    rs_valid <= '1';
                else
                    rs_value <= entries(rs_entry).value;
                    rs_valid <= entries(rs_entry).done;
                end if;
            end if;
            if rt_found then
                rt_tag <= std_logic_vector(to_unsigned(rt_entry, tag_t'length));
                if unsigned(cdb_tag) = rt_entry then
                    rt_value <= cdb_value;
                    rt_valid <= '1';
                else
                    rt_value <= entries(rt_entry).value;
                    rt_valid <= entries(rt_entry).done;
                end if;
            end if;
        end if;
    end process;

    rob_tail  <= std_logic_vector(tail);
    flush_tag <= flush_tag_reg;

end rtl;
