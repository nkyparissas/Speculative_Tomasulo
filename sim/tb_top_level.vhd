-- Speculative Tomasulo processor
-- Vibecoded by Nick Kyparissas using Claude Opus 5.5, based on the original
-- Speculative Tomasulo project (see README.md).
--
-- TB_TOP_LEVEL: testbench for the speculative Tomasulo processor.
--
-- The testbench resets the processor, lets it execute the program stored in
-- ROM_FILE for RUN_CYCLES clock cycles and, optionally, signals an exception
-- for the instruction that occupies ROB entry EXCEPTION_ROB_TAG. It does not
-- check any results itself. Instead, tests/run_tests.py records the simulated
-- behaviour as a cycle-level trace and compares it against golden traces and
-- against the reference model of tools/assembler.py.
--
-- Cycle k denotes rising clock edge k, which occurs at (k + 1) * PERIOD
-- because the clock starts high. Reset is sampled high only on cycle 0, and
-- the first instruction issues on cycle 2.
--
-- Generics:
--   ROM_FILE           ROM image loaded by the fetch unit (1024 lines of 19
--                      bits, as written by tools/assembler.py)
--   RUN_CYCLES         number of clock cycles to simulate
--   EXCEPTION_CYCLE    cycle on which the ROB samples exception_flag = '1'; the
--                      flag stays high for exactly one cycle, and values below
--                      2 disable the exception
--   EXCEPTION_ROB_TAG  ROB tag of the instruction that raises the exception
--   EXCEPTION_TAG_HELD true if exception_tag keeps its value after the flag
--                      drops, false if it returns to 0 together with the flag
--
-- The default values reproduce the testbench of the original project, which
-- raises an exception for ROB entry 3 on cycle 7.
--
-- Note that the stimulus changes at the same simulation time as a rising clock
-- edge. Since clk is driven from tb_clock by a concurrent assignment, the edge
-- reaches the processor one delta cycle later, in the same delta cycle as the
-- stimulus. Consequently, flip-flops sample a new stimulus value on that very
-- edge, whereas combinational paths that start at a stimulus signal (e.g. the
-- reservation stations' acknowledge, which depends on rst) only affect the
-- following edge. The golden traces depend on this alignment; hence, neither
-- the clock assignment nor the stimulus timing can change without re-blessing
-- them.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_top_level is
    generic (
        ROM_FILE           : string   := "rom.data";
        RUN_CYCLES         : positive := 108;
        EXCEPTION_CYCLE    : integer  := 7;
        EXCEPTION_ROB_TAG  : natural  := 3;
        EXCEPTION_TAG_HELD : boolean  := true);
end tb_top_level;

architecture tb of tb_top_level is

    constant PERIOD : time := 10 ns;

    signal clk            : std_logic;
    signal rst            : std_logic;
    signal exception_flag : std_logic;
    signal exception_tag  : std_logic_vector(3 downto 0);
    signal exception_pc   : std_logic_vector(9 downto 0);

    signal tb_clock     : std_logic := '1';
    signal tb_sim_ended : std_logic := '0';

begin

    dut : entity work.top_level
        generic map (
            ROM_FILE => ROM_FILE)
        port map (
            clk            => clk,
            rst            => rst,
            exception_flag => exception_flag,
            exception_tag  => exception_tag,
            exception_pc   => exception_pc);

    -- The clock stops once the stimulus process ends the simulation.
    tb_clock <= not tb_clock after PERIOD / 2 when tb_sim_ended /= '1' else '0';

    -- This assignment delays the clock by one delta cycle (see the note above).
    clk <= tb_clock;

    stimuli : process
    begin
        rst            <= '1';
        exception_flag <= '0';
        exception_tag  <= (others => '0');

        -- Reset is released at the time of cycle 1 (see the note above).
        wait for 2 * PERIOD;
        rst <= '0';

        if EXCEPTION_CYCLE >= 2 then
            wait for (EXCEPTION_CYCLE - 1) * PERIOD;
            exception_flag <= '1';
            exception_tag  <= std_logic_vector(to_unsigned(EXCEPTION_ROB_TAG, exception_tag'length));
            wait for PERIOD;
            exception_flag <= '0';
            if not EXCEPTION_TAG_HELD then
                exception_tag <= (others => '0');
            end if;
        end if;

        if now < (RUN_CYCLES + 1) * PERIOD then
            wait for (RUN_CYCLES + 1) * PERIOD - now;
        end if;
        tb_sim_ended <= '1';
        wait;
    end process;

end tb;
