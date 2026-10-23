-- Speculative Tomasulo processor
-- Vibecoded by Nick Kyparissas using Claude Opus 5.5, based on the original
-- Speculative Tomasulo project (see README.md).
--
-- RESERVATION_STATIONS: issue buffer of one execution unit.
--
-- The reservation stations hold the issued instructions of one execution unit
-- until both of their source operands are available, and then dispatch them
-- to the unit's functional unit. They implement the central idea of
-- Tomasulo's algorithm: an operand that is not yet available is represented
-- by the tag of the ROB entry that will produce it, and the station captures
-- the value as soon as that tag appears on the common data bus (CDB). The
-- generics configure one instance per execution unit; the processor uses
-- three stations for the arithmetic unit and two for the logical unit.
--
-- An instruction passes through a station in three steps. (1) Issue: if the
-- presented instruction belongs to UNIT and a station is free (ack = '1'),
-- the lowest free station records the function code and the tag of the
-- instruction's ROB entry, which is the current ROB tail. (2) Operands: in
-- the next cycle, the station receives the results of the operand lookup
-- that the ROB and the register file performed during issue, i.e. for each
-- operand either its value or the tag of the ROB entry that will produce it.
-- From then on, a missing operand is captured when its tag appears on the
-- CDB, already in the cycle of the operand fill itself. (3) Dispatch: the
-- lowest station whose operands were both available at the start of the
-- cycle moves to the functional unit and is released, provided that the
-- functional unit can accept another operation (fu_ready).
--
-- While the ROB reports a flush (flush_tag /= TAG_NONE), every station whose
-- tag lies in the circular range from flush_tag up to the ROB tail is
-- released instead. No instruction issues during a flush, since ack is low.
--
-- Names:
--   UNIT          execution unit served
--   NUM_STATIONS  number of stations
--   ack           the presented instruction is accepted in this cycle
--   rob_tail      tag of the ROB entry allocated to the presented instruction
--   rob_full      all ROB entries are occupied, so no instruction can issue
--   rob_*_tag     ROB lookup: TAG_NONE if the register file is up to date,
--                 otherwise the youngest ROB entry that writes the register
--   rob_*_value   ROB lookup: value of that entry, valid if rob_*_valid = '1'
--   rf_*_value    register file contents of rs and rt
--   flush_tag     first ROB entry to discard, TAG_NONE if there is no flush
--   cdb_*         tag and value on the common data bus
--   fu_ready      the functional unit can accept an operation
--   fu_op         operation dispatched to the functional unit
--   stations      contents of the stations (see rs_entry_t)
--   fill_pending  the station was issued in the previous cycle and waits for
--                 its operands

library ieee;
use ieee.std_logic_1164.all;
use work.tomasulo_pkg.all;

entity reservation_stations is
    generic (
        UNIT         : unit_t;
        NUM_STATIONS : positive);
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        -- Issue
        instruction  : in  instr_t;
        ack          : out std_logic;
        rob_tail     : in  tag_t;
        rob_full     : in  std_logic;
        -- Operand sources, one cycle after issue
        rob_rs_tag   : in  tag_t;
        rob_rt_tag   : in  tag_t;
        rob_rs_value : in  word_t;
        rob_rt_value : in  word_t;
        rob_rs_valid : in  std_logic;
        rob_rt_valid : in  std_logic;
        rf_rs_value  : in  word_t;
        rf_rt_value  : in  word_t;
        -- Flush and common data bus
        flush_tag    : in  tag_t;
        cdb_tag      : in  tag_t;
        cdb_value    : in  word_t;
        -- Dispatch to the functional unit
        fu_ready     : in  std_logic;
        fu_op        : out operation_t);
end reservation_stations;

architecture rtl of reservation_stations is

    type station_array_t is array (0 to NUM_STATIONS - 1) of rs_entry_t;

    function any_free(stations : station_array_t) return boolean is
    begin
        for i in stations'range loop
            if stations(i).busy = '0' then
                return true;
            end if;
        end loop;
        return false;
    end function any_free;

    signal stations     : station_array_t := (others => RS_ENTRY_EMPTY);
    signal fill_pending : std_logic_vector(0 to NUM_STATIONS - 1) := (others => '0');
    signal ack_i        : std_logic;

begin

    -- The issue step below tests ack_i rather than repeating this condition,
    -- so that the stations, the fetch unit and the ROB all act on the same
    -- issue decision in every cycle.
    ack_i <= '1' when instruction(UNIT_FIELD) = UNIT and rst = '0' and flush_tag = TAG_NONE
                      and rob_full = '0' and any_free(stations) else
             '0';
    ack <= ack_i;

    process
        -- New contents of the station being processed.
        variable s          : rs_entry_t;
        variable issued     : boolean;
        variable dispatched : boolean;

        -- Operand as reported by the lookup of the issue cycle: the value in
        -- the ROB entry of its producer, or that entry's tag if the result is
        -- still pending, or the register file's value if no ROB entry writes
        -- the register.
        procedure fill(variable v : out word_t; variable q : out tag_t;
                       rob_tag : tag_t; rob_valid : std_logic; rob_value, rf_value : word_t) is
        begin
            q := TAG_NONE;
            if rob_tag = TAG_NONE then
                v := rf_value;
            else
                v := rob_value;
                if rob_valid = '0' then
                    q := rob_tag;
                end if;
            end if;
        end procedure fill;

        -- Captures a missing operand whose producer broadcasts on the CDB.
        procedure capture(variable v : inout word_t; variable q : inout tag_t) is
        begin
            if q /= TAG_NONE and q = cdb_tag then
                v := cdb_value;
                q := TAG_NONE;
            end if;
        end procedure capture;
    begin
        wait until rising_edge(clk);
        fu_op.tag <= TAG_NONE;
        if rst = '1' then
            stations     <= (others => RS_ENTRY_EMPTY);
            fill_pending <= (others => '0');
            fu_op        <= OPERATION_NONE;
        else
            issued     := false;
            dispatched := false;
            for i in stations'range loop
                s := stations(i);
                if s.busy = '1' and in_flush_range(s.tag, flush_tag, rob_tail) then
                    -- Flush: the instruction is discarded.
                    s := RS_ENTRY_EMPTY;
                    fill_pending(i) <= '0';

                elsif s.busy = '0' then
                    -- (1) Issue into the lowest free station.
                    if ack_i = '1' and not issued then
                        s.busy := '1';
                        s.fop  := instruction(FOP_FIELD);
                        s.tag  := rob_tail;
                        fill_pending(i) <= '1';
                        issued := true;
                    end if;

                else
                    -- (2) Operands: the lookup results arrive one cycle after
                    -- issue, and a missing operand is captured from the CDB.
                    if fill_pending(i) = '1' then
                        fill(s.v1, s.q1, rob_rs_tag, rob_rs_valid, rob_rs_value, rf_rs_value);
                        fill(s.v2, s.q2, rob_rt_tag, rob_rt_valid, rob_rt_value, rf_rt_value);
                        fill_pending(i) <= '0';
                    end if;
                    capture(s.v1, s.q1);
                    capture(s.v2, s.q2);

                    -- (3) Dispatch the lowest station that was ready at the
                    -- start of the cycle, i.e. before this cycle's captures.
                    if fu_ready = '1' and not dispatched
                       and stations(i).q1 = TAG_NONE and stations(i).q2 = TAG_NONE then
                        fu_op <= (tag => s.tag, fop => s.fop, a => s.v1, b => s.v2);
                        s := RS_ENTRY_EMPTY;
                        dispatched := true;
                    end if;
                end if;
                stations(i) <= s;
            end loop;
        end if;
    end process;

end rtl;
