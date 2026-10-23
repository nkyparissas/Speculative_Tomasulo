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
-- In every cycle, the clocked process performs five regular steps in order.
-- (1) Issue: if the presented instruction belongs to UNIT and a station is
-- free (ack = '1'), the lowest free station records the function code and
-- the tag of the instruction's ROB entry, which is the current ROB tail.
-- (2) Wakeup: every busy station whose q1 or q2 equals the tag on the CDB
-- captures the broadcast value. (3) Operand fill: one cycle after issue, the
-- new station copies its operands from the ROB lookup if the ROB returned a
-- tag for the register, or from the CDB if that tag is being broadcast in the
-- same cycle, and from the register file otherwise. (4) Dispatch:
-- the lowest station with both operands available moves to the functional
-- unit and is released, provided that the in-flight counter shows room in the
-- unit's pipeline. (5) Credit return: the counter decreases whenever the CDB
-- grants the bus to this unit, since a result then leaves the pipeline.
--
-- All steps assign signals of one clocked process; hence, where two steps
-- assign the same field in the same cycle, the later step takes effect. In
-- particular, the operand fill overrides a wakeup of the same station, which
-- is why the fill itself takes a value that the CDB broadcasts in that cycle,
-- and the credit return overrides the increment of a simultaneous dispatch,
-- which is why it keeps the count unchanged in that case. These priorities
-- are part of the verified behaviour, so the steps must keep their order.
--
-- While the ROB reports a flush (flush_tag /= TAG_NONE), a sixth step
-- releases every station whose tag lies in the circular range from flush_tag
-- up to the ROB tail and cancels its pending operand fill. These stations
-- take part in no other step in that cycle, whereas all other stations
-- proceed as usual. No instruction issues during a flush, since ack is low.
--
-- Names:
--   UNIT            execution unit served, also its CDB grant code
--   NUM_STATIONS    number of stations
--   PIPELINE_DEPTH  stages of the functional unit, i.e. maximum in-flight operations
--   ack             the presented instruction is accepted in this cycle
--   rob_tail        tag of the ROB entry allocated to the presented instruction
--   rob_full        all ROB entries are occupied, so no instruction can issue
--   rob_*_tag       ROB lookup: TAG_NONE if the register file is up to date,
--                   otherwise the youngest ROB entry that writes the register
--   rob_*_value     ROB lookup: value of that entry, valid if rob_*_valid = '1'
--   rf_*_value      register file contents of rs and rt
--   flush_tag       first ROB entry to discard, TAG_NONE if there is no flush
--   cdb_*           tag, value and grant of the common data bus
--   fu_*            operation dispatched to the functional unit; fu_tag is
--                   TAG_NONE in cycles without a dispatch
--   stations        contents of the stations (see rs_entry_t)
--   fill_pending    the station was issued in the previous cycle and waits
--                   for its operand fill
--   in_flight       operations dispatched whose results have not left the
--                   functional unit yet

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tomasulo_pkg.all;

entity reservation_stations is
    generic (
        UNIT           : unit_t;
        NUM_STATIONS   : positive;
        PIPELINE_DEPTH : positive);
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
        -- Flush
        flush_tag    : in  tag_t;
        -- Common data bus
        cdb_tag      : in  tag_t;
        cdb_value    : in  word_t;
        cdb_grant    : in  unit_t;
        -- Dispatch to the functional unit
        fu_tag       : out tag_t;
        fu_fop       : out fop_t;
        fu_a         : out word_t;
        fu_b         : out word_t);
end reservation_stations;

architecture rtl of reservation_stations is

    type station_array_t is array (NUM_STATIONS - 1 downto 0) of rs_entry_t;
    type flag_array_t    is array (NUM_STATIONS - 1 downto 0) of boolean;

    function any_free(stations : station_array_t) return boolean is
        variable free : boolean := false;
    begin
        for i in stations'range loop
            if stations(i).busy = '0' then
                free := true;
            end if;
        end loop;
        return free;
    end function any_free;

    signal stations     : station_array_t := (others => RS_ENTRY_EMPTY);
    signal fill_pending : std_logic_vector(NUM_STATIONS - 1 downto 0) := (others => '0');
    signal in_flight    : natural range 0 to PIPELINE_DEPTH := 0;
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
        variable found   : boolean;
        variable discard : flag_array_t;
    begin
        wait until rising_edge(clk);
        if rst = '1' then
            stations     <= (others => RS_ENTRY_EMPTY);
            fill_pending <= (others => '0');
            in_flight    <= 0;
            fu_tag       <= TAG_NONE;
            fu_fop       <= (others => '0');
            fu_a         <= (others => '0');
            fu_b         <= (others => '0');

        else
            -- Stations of instructions that the ROB discards in this cycle;
            -- step (6) releases them, and they take part in no other step.
            for i in stations'range loop
                discard(i) := flush_tag /= TAG_NONE and in_flush_range(stations(i).tag, flush_tag, rob_tail);
            end loop;

            -- (1) Issue into the lowest free station. During a flush, ack_i is
            -- low, so no instruction issues.
            if instruction(UNIT_FIELD) = UNIT and ack_i = '1' then
                found := false;
                for i in 0 to NUM_STATIONS - 1 loop
                    if not found and stations(i).busy = '0' then
                        stations(i).busy <= '1';
                        stations(i).fop  <= instruction(FOP_FIELD);
                        stations(i).tag  <= rob_tail;
                        fill_pending(i)  <= '1';
                        found := true;
                    end if;
                end loop;
            end if;

            -- (2) Wakeup from the CDB.
            for i in stations'range loop
                if cdb_tag = stations(i).q1 and cdb_tag /= TAG_NONE and stations(i).busy = '1' then
                    stations(i).v1 <= cdb_value;
                    stations(i).q1 <= TAG_NONE;
                end if;
                if cdb_tag = stations(i).q2 and cdb_tag /= TAG_NONE and stations(i).busy = '1' then
                    stations(i).v2 <= cdb_value;
                    stations(i).q2 <= TAG_NONE;
                end if;
            end loop;

            -- (3) Operand fill of the lowest station issued in the previous
            -- cycle. The lookup results describe the ROB at the time of issue,
            -- so a producer that broadcasts its result in this very cycle is
            -- still reported as pending. Since this step overrides the wakeup
            -- of step (2), it takes such a value from the CDB itself.
            found := false;
            for i in 0 to NUM_STATIONS - 1 loop
                if not found and fill_pending(i) = '1' and not discard(i) then
                    if rob_rs_tag /= TAG_NONE then
                        stations(i).v1 <= rob_rs_value;
                        if rob_rs_valid = '1' then
                            stations(i).q1 <= TAG_NONE;
                        elsif rob_rs_tag = cdb_tag then
                            stations(i).v1 <= cdb_value;
                            stations(i).q1 <= TAG_NONE;
                        else
                            stations(i).q1 <= rob_rs_tag;
                        end if;
                    else
                        stations(i).v1 <= rf_rs_value;
                        stations(i).q1 <= TAG_NONE;
                    end if;

                    if rob_rt_tag /= TAG_NONE then
                        stations(i).v2 <= rob_rt_value;
                        if rob_rt_valid = '1' then
                            stations(i).q2 <= TAG_NONE;
                        elsif rob_rt_tag = cdb_tag then
                            stations(i).v2 <= cdb_value;
                            stations(i).q2 <= TAG_NONE;
                        else
                            stations(i).q2 <= rob_rt_tag;
                        end if;
                    else
                        stations(i).v2 <= rf_rt_value;
                        stations(i).q2 <= TAG_NONE;
                    end if;

                    fill_pending(i) <= '0';
                    found := true;
                end if;
            end loop;

            -- (4) Dispatch the lowest ready station and release it.
            found := false;
            if in_flight < PIPELINE_DEPTH then
                for i in 0 to NUM_STATIONS - 1 loop
                    if not found and stations(i).busy = '1' and not discard(i)
                       and stations(i).q1 = TAG_NONE and stations(i).q2 = TAG_NONE then
                        fu_tag      <= stations(i).tag;
                        fu_fop      <= stations(i).fop;
                        fu_a        <= stations(i).v1;
                        fu_b        <= stations(i).v2;
                        in_flight   <= in_flight + 1;
                        stations(i) <= RS_ENTRY_EMPTY;
                        found := true;
                    end if;
                end loop;
            end if;
            if not found then
                fu_tag <= TAG_NONE;
            end if;

            -- (5) Credit return: a result of this unit occupies the CDB. If an
            -- operation was dispatched in the same cycle, one operation enters
            -- the pipeline as another one leaves, so the count stays as it was.
            if cdb_grant = UNIT and in_flight /= 0 then
                if found then
                    in_flight <= in_flight;
                else
                    in_flight <= in_flight - 1;
                end if;
            end if;

            -- (6) Flush: release the discarded stations and cancel their
            -- pending operand fill.
            for i in stations'range loop
                if discard(i) then
                    stations(i)     <= RS_ENTRY_EMPTY;
                    fill_pending(i) <= '0';
                end if;
            end loop;
        end if;
    end process;

end rtl;
