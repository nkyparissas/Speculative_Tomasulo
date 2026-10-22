-- Speculative Tomasulo processor
-- Vibecoded by Nick Kyparissas using Claude Opus 5.5, based on the original
-- Speculative Tomasulo project (see README.md).
--
-- COMMON_DATA_BUS: arbiter and multiplexer of the result bus.
--
-- The common data bus (CDB) broadcasts one result per cycle, together with
-- the tag of the ROB entry that it belongs to, to the reservation stations
-- and the reorder buffer. Both functional units request the bus, and the
-- arbiter registers its decision: a grant decided on a rising edge applies to
-- the following cycle, during which the bus carries the last pipeline stage of
-- the granted unit. When both units request the bus, the arbiter alternates
-- between them (round robin); after reset, the logical unit wins the first
-- tie. Without a grant, the bus carries TAG_NONE and a zero value.
--
-- The grant also informs the functional units that their last stage is being
-- consumed and the reservation stations that a pipeline slot is released.
--
-- Names:
--   req_*, tag_*, value_*  request and last pipeline stage of each functional unit
--   grant                  owner of the bus in this cycle: a unit code or GRANT_NONE
--   cdb_tag, cdb_value     broadcast result
--   last_winner            unit that won the most recent grant, for round robin

library ieee;
use ieee.std_logic_1164.all;
use work.tomasulo_pkg.all;

entity common_data_bus is
    port (
        clk              : in  std_logic;
        rst              : in  std_logic;
        req_logical      : in  std_logic;
        req_arithmetic   : in  std_logic;
        tag_logical      : in  tag_t;
        tag_arithmetic   : in  tag_t;
        value_logical    : in  word_t;
        value_arithmetic : in  word_t;
        grant            : out unit_t;
        cdb_tag          : out tag_t;
        cdb_value        : out word_t);
end common_data_bus;

architecture rtl of common_data_bus is

    signal grant_reg   : unit_t := GRANT_NONE;
    signal last_winner : unit_t := UNIT_ARITHMETIC;

begin

    process
    begin
        wait until rising_edge(clk);
        if rst = '1' then
            grant_reg   <= GRANT_NONE;
            last_winner <= UNIT_ARITHMETIC;
        elsif req_arithmetic = '1' and req_logical = '1' then
            if last_winner = UNIT_ARITHMETIC then
                grant_reg   <= UNIT_LOGICAL;
                last_winner <= UNIT_LOGICAL;
            else
                grant_reg   <= UNIT_ARITHMETIC;
                last_winner <= UNIT_ARITHMETIC;
            end if;
        elsif req_arithmetic = '1' then
            grant_reg   <= UNIT_ARITHMETIC;
            last_winner <= UNIT_ARITHMETIC;
        elsif req_logical = '1' then
            grant_reg   <= UNIT_LOGICAL;
            last_winner <= UNIT_LOGICAL;
        else
            grant_reg <= GRANT_NONE;
        end if;
    end process;

    grant <= grant_reg;

    cdb_value <= value_arithmetic when grant_reg = UNIT_ARITHMETIC else
                 value_logical    when grant_reg = UNIT_LOGICAL    else
                 (others => '0');

    cdb_tag <= tag_arithmetic when grant_reg = UNIT_ARITHMETIC else
               tag_logical    when grant_reg = UNIT_LOGICAL    else
               TAG_NONE;

end rtl;
