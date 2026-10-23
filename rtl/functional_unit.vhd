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
-- behind it still advance into empty slots, so the unit can hold up to
-- PIPELINE_DEPTH results. The unit is ready for another operation as long as
-- a stage remains free for it, counting the operation that arrives in the
-- current cycle, so the reservation stations never dispatch into a full
-- pipeline. During a flush, the stages of discarded instructions become
-- empty, and an arriving operation of a discarded instruction is dropped.
--
-- Since the arbiter of the CDB registers its decision, the unit requests the
-- bus one cycle in advance: it requests when the last stage holds a result
-- that is not granted in the current cycle, or when the second-to-last stage
-- holds a result, in anticipation of its move into the last stage. Hence,
-- PIPELINE_DEPTH must be at least 2.
--
-- Names:
--   UNIT             execution unit; selects the operations and the grant code
--   PIPELINE_DEPTH   number of pipeline stages
--   op               dispatched operation; op.tag is TAG_NONE if there is none
--   ready            the unit can accept an operation in the next cycle
--   cdb_req          request for the CDB
--   cdb_grant        current owner of the CDB
--   flush_tag        first discarded ROB entry during a flush, TAG_NONE otherwise
--   rob_tail         ROB tail, which ends the discarded range
--   tag_out, result  last pipeline stage, as seen by the CDB
--   tags, values     pipeline stages; a stage is empty when its tag is TAG_NONE
--   alu              result of the dispatched operation

library ieee;
use ieee.std_logic_1164.all;
use work.tomasulo_pkg.all;

entity functional_unit is
    generic (
        UNIT           : unit_t;
        PIPELINE_DEPTH : positive);
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        op        : in  operation_t;
        ready     : out std_logic;
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

    -- Number of operations in the pipeline, including the arriving one.
    function occupancy(tags : tag_pipe_t; arriving : tag_t) return natural is
        variable n : natural := 0;
    begin
        for k in tags'range loop
            if tags(k) /= TAG_NONE then
                n := n + 1;
            end if;
        end loop;
        if arriving /= TAG_NONE then
            n := n + 1;
        end if;
        return n;
    end function occupancy;

    signal tags   : tag_pipe_t   := (others => TAG_NONE);
    signal values : value_pipe_t := (others => (others => '0'));
    signal alu    : word_t;

begin

    alu <= execute(UNIT, op.fop, op.a, op.b);

    ready   <= '1' when occupancy(tags, op.tag) < PIPELINE_DEPTH else '0';
    cdb_req <= '1' when (tags(LAST) /= TAG_NONE and cdb_grant /= UNIT) or tags(LAST - 1) /= TAG_NONE else
               '0';
    tag_out <= tags(LAST);
    result  <= values(LAST);

    process
        -- Tags of the stages after this cycle's flush.
        variable live       : tag_pipe_t;
        variable free_stage : integer;

        -- The tag of an operation, or TAG_NONE if a flush discards it.
        impure function kept(tag : tag_t) return tag_t is
        begin
            if in_flush_range(tag, flush_tag, rob_tail) then
                return TAG_NONE;
            end if;
            return tag;
        end function kept;
    begin
        wait until rising_edge(clk);
        if rst = '1' then
            tags <= (others => TAG_NONE);
        else
            for k in 0 to LAST loop
                live(k) := kept(tags(k));
            end loop;

            -- The highest stage that can accept data limits the shift: the
            -- last stage can if it is empty or granted the bus, any other
            -- stage only if it is empty. Stages above it hold their contents.
            free_stage := -1;
            for k in 0 to LAST loop
                if live(k) = TAG_NONE or (k = LAST and cdb_grant = UNIT) then
                    free_stage := k;
                end if;
            end loop;

            tags <= live;
            if free_stage >= 0 then
                for k in 1 to LAST loop
                    if k <= free_stage then
                        tags(k)   <= live(k - 1);
                        values(k) <= values(k - 1);
                    end if;
                end loop;
                tags(0)   <= kept(op.tag);
                values(0) <= alu;
            end if;
        end if;
    end process;

end rtl;
