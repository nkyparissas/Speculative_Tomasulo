-- Speculative Tomasulo processor
-- Vibecoded by Nick Kyparissas using Claude Opus 5.5, based on the original
-- Speculative Tomasulo project (see README.md).
--
-- FUNCTIONAL_UNIT: pipelined ALU of one execution unit.
--
-- The functional unit executes the operations that its reservation stations
-- dispatch and returns the results, together with their tags, to the common
-- data bus (CDB). The operation itself is computed combinationally as it
-- enters stage 0 (see execute in tomasulo_pkg), and the result then travels
-- through PIPELINE_DEPTH stages to model the latency of a real unit; only the
-- last stage is visible to the CDB. The processor uses three stages for the
-- arithmetic unit and two for the logical unit.
--
-- The pipeline is elastic. While the last stage waits for the bus, the stages
-- behind it still advance into empty slots, so the unit can buffer up to
-- PIPELINE_DEPTH results. An operation that arrives while every stage is
-- occupied would be lost; the in-flight counter of the reservation stations
-- prevents this, since it never admits more than PIPELINE_DEPTH operations.
-- During a flush, operations of discarded instructions are marked rather than
-- removed: they drain like all others, which keeps the requests, the grants
-- and the in-flight counter of the stations exact, but their results reach
-- the CDB without a tag, so they complete no ROB entry and wake up no station.
--
-- Since the arbiter of the CDB registers its decision, the unit requests the
-- bus one cycle in advance: it requests when the last stage holds a result
-- that is not granted in the current cycle, or when the second-to-last stage
-- holds a result, in anticipation of its move into the last stage. Hence,
-- PIPELINE_DEPTH must be at least 2.
--
-- Names:
--   UNIT               execution unit; selects the operations and the grant code
--   PIPELINE_DEPTH     number of pipeline stages
--   tag_in, fop, a, b  dispatched operation; tag_in is TAG_NONE if there is none
--   cdb_req            request for the CDB
--   cdb_grant          current owner of the CDB
--   tag_out, result    last pipeline stage, as seen by the CDB
--   flush_tag, rob_tail  first discarded ROB entry during a flush, TAG_NONE
--                      otherwise, and the ROB tail that ends the discarded range
--   tags, values       pipeline stages; a stage is empty when its tag is TAG_NONE
--   discarded          the operation in the stage belongs to a discarded instruction
--   alu                result of the dispatched operation

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tomasulo_pkg.all;

entity functional_unit is
    generic (
        UNIT           : unit_t;
        PIPELINE_DEPTH : positive);
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        tag_in    : in  tag_t;
        fop       : in  fop_t;
        a         : in  word_t;
        b         : in  word_t;
        cdb_req   : out std_logic;
        cdb_grant : in  unit_t;
        flush_tag : in  tag_t;
        rob_tail  : in  tag_t;
        tag_out   : out tag_t;
        result    : out word_t);
end functional_unit;

architecture rtl of functional_unit is

    constant LAST : natural := PIPELINE_DEPTH - 1;

    type tag_pipe_t   is array (LAST downto 0) of tag_t;
    type value_pipe_t is array (LAST downto 0) of word_t;

    signal tags   : tag_pipe_t   := (others => TAG_NONE);
    signal values : value_pipe_t := (others => (others => '0'));
    signal discarded : std_logic_vector(LAST downto 0) := (others => '0');
    signal alu    : word_t;

begin

    alu <= execute(UNIT, fop, a, b);

    cdb_req <= '1' when (tags(LAST) /= TAG_NONE and cdb_grant /= UNIT) or tags(LAST - 1) /= TAG_NONE else
               '0';
    tag_out <= TAG_NONE when discarded(LAST) = '1' else tags(LAST);
    result  <= values(LAST);

    process
        variable free_stage : integer;
        variable marked     : std_logic_vector(LAST downto 0);
    begin
        wait until rising_edge(clk);
        if rst = '1' then
            tags      <= (others => TAG_NONE);
            discarded <= (others => '0');
        else
            -- Marks after a possible flush in this cycle. They stay with
            -- their operation, so a stage that shifts below takes the mark of
            -- the stage that moves into it.
            for k in 0 to LAST loop
                if flush_tag /= TAG_NONE and in_flush_range(tags(k), flush_tag, rob_tail) then
                    marked(k) := '1';
                else
                    marked(k) := discarded(k);
                end if;
            end loop;
            discarded <= marked;

            -- The highest stage that can accept data limits the shift: the
            -- last stage can if it is empty or granted the bus, any other
            -- stage only if it is empty. Stages above it hold their contents.
            free_stage := -1;
            for k in 0 to LAST loop
                if tags(k) = TAG_NONE or (k = LAST and cdb_grant = UNIT) then
                    free_stage := k;
                end if;
            end loop;

            if free_stage >= 0 then
                for k in 1 to LAST loop
                    if k <= free_stage then
                        tags(k)      <= tags(k - 1);
                        values(k)    <= values(k - 1);
                        discarded(k) <= marked(k - 1);
                    end if;
                end loop;
                tags(0)   <= tag_in;
                values(0) <= alu;
                if flush_tag /= TAG_NONE and in_flush_range(tag_in, flush_tag, rob_tail) then
                    discarded(0) <= '1';
                else
                    discarded(0) <= '0';
                end if;
            end if;
        end if;
    end process;

end rtl;
