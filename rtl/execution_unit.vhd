-- Speculative Tomasulo processor
-- Vibecoded by Nick Kyparissas using Claude Opus 5.5, based on the original
-- Speculative Tomasulo project (see README.md).
--
-- EXECUTION_UNIT: reservation stations and functional unit of one unit type.
--
-- An execution unit combines a set of reservation stations with the
-- pipelined functional unit that they dispatch to. The wrapper hides the
-- dispatch interface between the two, so the top level instantiates one
-- execution unit per instruction type and connects it to the issue stage,
-- the reorder buffer and the common data bus. The generics are passed on
-- unchanged; UNIT selects both the instructions that the stations accept and
-- the operations that the functional unit performs.
--
-- Names:
--   UNIT, NUM_STATIONS, PIPELINE_DEPTH  see RESERVATION_STATIONS and FUNCTIONAL_UNIT
--   cdb_req, result_tag, result         request and last pipeline stage of the functional unit
--   fu_tag, fu_fop, fu_a, fu_b          dispatch from the stations to the functional unit
--   all other ports                     see RESERVATION_STATIONS

library ieee;
use ieee.std_logic_1164.all;
use work.tomasulo_pkg.all;

entity execution_unit is
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
        cdb_req      : out std_logic;
        result_tag   : out tag_t;
        result       : out word_t);
end execution_unit;

architecture structural of execution_unit is

    signal fu_tag : tag_t;
    signal fu_fop : fop_t;
    signal fu_a   : word_t;
    signal fu_b   : word_t;

begin

    u_rs : entity work.reservation_stations
        generic map (
            UNIT           => UNIT,
            NUM_STATIONS   => NUM_STATIONS,
            PIPELINE_DEPTH => PIPELINE_DEPTH)
        port map (
            clk          => clk,
            rst          => rst,
            instruction  => instruction,
            ack          => ack,
            rob_tail     => rob_tail,
            rob_rs_tag   => rob_rs_tag,
            rob_rt_tag   => rob_rt_tag,
            rob_rs_value => rob_rs_value,
            rob_rt_value => rob_rt_value,
            rob_rs_valid => rob_rs_valid,
            rob_rt_valid => rob_rt_valid,
            rf_rs_value  => rf_rs_value,
            rf_rt_value  => rf_rt_value,
            flush_tag    => flush_tag,
            cdb_tag      => cdb_tag,
            cdb_value    => cdb_value,
            cdb_grant    => cdb_grant,
            fu_tag       => fu_tag,
            fu_fop       => fu_fop,
            fu_a         => fu_a,
            fu_b         => fu_b);

    u_fu : entity work.functional_unit
        generic map (
            UNIT           => UNIT,
            PIPELINE_DEPTH => PIPELINE_DEPTH)
        port map (
            clk       => clk,
            rst       => rst,
            tag_in    => fu_tag,
            fop       => fu_fop,
            a         => fu_a,
            b         => fu_b,
            cdb_req   => cdb_req,
            cdb_grant => cdb_grant,
            tag_out   => result_tag,
            result    => result);

end structural;
