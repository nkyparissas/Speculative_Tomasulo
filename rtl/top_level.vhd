-- Speculative Tomasulo processor
-- Vibecoded by Nick Kyparissas using Claude Opus 5.5, based on the original
-- Speculative Tomasulo project (see README.md).
--
-- TOP_LEVEL: out-of-order processor with hardware-based speculation.
--
-- The processor executes the program in its instruction ROM with Tomasulo's
-- algorithm extended by a reorder buffer (ROB). Instructions issue in program
-- order, one per cycle, into the reservation stations of their execution
-- unit, execute out of order as soon as their operands are available, and
-- commit in program order from the ROB. There are two execution units, each
-- consisting of reservation stations and a pipelined functional unit: a
-- logical unit (OR, AND, NOT) with two stations and two pipeline stages, and
-- an arithmetic unit (ADD, SUB, shift left) with three stations and three
-- stages. The units return their results over a single common data bus
-- (CDB), which wakes up waiting reservation stations and fills the ROB.
--
-- An instruction proceeds as follows. In the issue cycle, the fetch unit
-- presents it, the reservation stations of its unit accept it if a station
-- is free (ack_*), the ROB allocates the entry rob_tail for it, and both the
-- register file and the ROB look up its source registers. In the next cycle,
-- the station copies the operands, either as values or as tags of the ROB
-- entries that will produce them. The station dispatches the instruction once
-- both operands are available, the functional unit broadcasts the result on
-- the CDB after its pipeline latency, and the ROB commits the result to the
-- register file once all older instructions have committed.
--
-- Exceptions are requested from outside: exception_flag, raised for one
-- cycle, reports that the instruction in ROB entry exception_tag has faulted.
-- The ROB and the reservation stations then discard that instruction and all
-- younger ones, and exception_pc reports the program counter of the faulting
-- instruction. Instruction fetch is not redirected, so the program continues
-- with the instructions that follow the last issued one.
--
-- See doc/known_issues.md for deviations from the intended behaviour, which
-- the regression tests in tests/ currently preserve.
--
-- Names:
--   ROM_FILE                    program image, see INSTRUCTION_FETCH
--   pc, instruction             instruction presented at the issue stage
--   ack_*, issue                the presented instruction is accepted by a unit
--   rob_tail                    ROB entry allocated to the presented instruction
--   rob_rs_*, rob_rt_*          ROB lookup results for the source registers
--   rf_rs_value, rf_rt_value    register file contents of the source registers
--   flush_tag                   first discarded ROB entry after an exception
--   cdb_req_*, tag_*, result_*  bus requests and results of the functional units
--   cdb_grant                   owner of the common data bus
--   cdb_tag, cdb_value          result broadcast on the common data bus
--   commit_*                    committed result written to the register file

library ieee;
use ieee.std_logic_1164.all;
use work.tomasulo_pkg.all;

entity top_level is
    generic (
        ROM_FILE : string := "rom.data");
    port (
        clk            : in  std_logic;
        rst            : in  std_logic;
        exception_flag : in  std_logic;
        exception_tag  : in  tag_t;
        exception_pc   : out pc_t);
end top_level;

architecture structural of top_level is

    signal pc          : pc_t;
    signal instruction : instr_t;

    signal ack_logical    : std_logic;
    signal ack_arithmetic : std_logic;
    signal issue          : std_logic;

    signal rob_tail     : tag_t;
    signal rob_rs_tag   : tag_t;
    signal rob_rt_tag   : tag_t;
    signal rob_rs_value : word_t;
    signal rob_rt_value : word_t;
    signal rob_rs_valid : std_logic;
    signal rob_rt_valid : std_logic;
    signal rf_rs_value  : word_t;
    signal rf_rt_value  : word_t;
    signal flush_tag    : tag_t;

    signal cdb_req_logical    : std_logic;
    signal cdb_req_arithmetic : std_logic;
    signal tag_logical        : tag_t;
    signal tag_arithmetic     : tag_t;
    signal result_logical     : word_t;
    signal result_arithmetic  : word_t;
    signal cdb_grant          : unit_t;
    signal cdb_tag            : tag_t;
    signal cdb_value          : word_t;

    signal commit_we    : std_logic;
    signal commit_rd    : reg_addr_t;
    signal commit_value : word_t;

begin

    -- At most one unit accepts the presented instruction, since the unit field
    -- selects exactly one of them.
    issue <= ack_logical or ack_arithmetic;

    u_fetch : entity work.instruction_fetch
        generic map (
            ROM_FILE => ROM_FILE)
        port map (
            clk         => clk,
            rst         => rst,
            advance     => issue,
            pc          => pc,
            instruction => instruction);

    u_regfile : entity work.register_file
        port map (
            clk          => clk,
            rst          => rst,
            commit_we    => commit_we,
            commit_rd    => commit_rd,
            commit_value => commit_value,
            rs_addr      => instruction(RS_FIELD),
            rt_addr      => instruction(RT_FIELD),
            rs_value     => rf_rs_value,
            rt_value     => rf_rt_value);

    u_logical : entity work.execution_unit
        generic map (
            UNIT           => UNIT_LOGICAL,
            NUM_STATIONS   => 2,
            PIPELINE_DEPTH => 2)
        port map (
            clk          => clk,
            rst          => rst,
            instruction  => instruction,
            ack          => ack_logical,
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
            cdb_req      => cdb_req_logical,
            result_tag   => tag_logical,
            result       => result_logical);

    u_arithmetic : entity work.execution_unit
        generic map (
            UNIT           => UNIT_ARITHMETIC,
            NUM_STATIONS   => 3,
            PIPELINE_DEPTH => 3)
        port map (
            clk          => clk,
            rst          => rst,
            instruction  => instruction,
            ack          => ack_arithmetic,
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
            cdb_req      => cdb_req_arithmetic,
            result_tag   => tag_arithmetic,
            result       => result_arithmetic);

    u_cdb : entity work.common_data_bus
        port map (
            clk              => clk,
            rst              => rst,
            req_logical      => cdb_req_logical,
            req_arithmetic   => cdb_req_arithmetic,
            tag_logical      => tag_logical,
            tag_arithmetic   => tag_arithmetic,
            value_logical    => result_logical,
            value_arithmetic => result_arithmetic,
            grant            => cdb_grant,
            cdb_tag          => cdb_tag,
            cdb_value        => cdb_value);

    u_rob : entity work.reorder_buffer
        port map (
            clk            => clk,
            rst            => rst,
            pc             => pc,
            issue          => issue,
            instruction    => instruction,
            rob_tail       => rob_tail,
            rs_tag         => rob_rs_tag,
            rt_tag         => rob_rt_tag,
            rs_value       => rob_rs_value,
            rt_value       => rob_rt_value,
            rs_valid       => rob_rs_valid,
            rt_valid       => rob_rt_valid,
            cdb_tag        => cdb_tag,
            cdb_value      => cdb_value,
            commit_we      => commit_we,
            commit_rd      => commit_rd,
            commit_value   => commit_value,
            exception_flag => exception_flag,
            exception_tag  => exception_tag,
            exception_pc   => exception_pc,
            flush_tag      => flush_tag);

end structural;
