-- Speculative Tomasulo processor
-- Vibecoded by Nick Kyparissas using Claude Opus 5.5, based on the original
-- Speculative Tomasulo project (see README.md).
--
-- REGISTER_FILE: architectural register file.
--
-- The register file holds the committed state of the NUM_REGS architectural
-- registers. The reorder buffer writes at most one committed result per cycle
-- through the commit port, while the issue stage reads the two source
-- registers (rs, rt) of the presented instruction. Both read ports are
-- registered, so their values reach the reservation stations one cycle after
-- issue, together with the results of the reorder buffer's operand lookup.
--
-- A read of the register that the commit port writes in the same cycle
-- returns the commit value instead of the stored one (write-first bypass),
-- so that the result is not read stale.
--
-- The processor has no load instructions. Therefore, reset initialises
-- registers r0 to r10 with their own index to provide input operands, and it
-- clears the remaining registers. Register r0 is an ordinary register rather
-- than a hard-wired zero.
--
-- Names:
--   commit_we, commit_rd, commit_value  write port, driven by the ROB
--   rs_addr, rt_addr                    source registers of the presented instruction
--   rs_value, rt_value                  registered read data
--   regs                                register contents

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tomasulo_pkg.all;

entity register_file is
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        commit_we    : in  std_logic;
        commit_rd    : in  reg_addr_t;
        commit_value : in  word_t;
        rs_addr      : in  reg_addr_t;
        rt_addr      : in  reg_addr_t;
        rs_value     : out word_t;
        rt_value     : out word_t);
end register_file;

architecture rtl of register_file is

    type reg_array_t is array (NUM_REGS - 1 downto 0) of word_t;

    function reset_contents return reg_array_t is
        variable regs : reg_array_t := (others => (others => '0'));
    begin
        for r in 0 to 10 loop
            regs(r) := std_logic_vector(to_unsigned(r, word_t'length));
        end loop;
        return regs;
    end function reset_contents;

    signal regs : reg_array_t := (others => (others => '0'));

begin

    process
        -- Contents of a register, including a value written in this cycle.
        impure function read_register(addr : reg_addr_t) return word_t is
        begin
            if commit_we = '1' and commit_rd = addr then
                return commit_value;
            end if;
            return regs(to_integer(unsigned(addr)));
        end function read_register;
    begin
        wait until rising_edge(clk);
        if rst = '1' then
            regs <= reset_contents;
        else
            if commit_we = '1' then
                regs(to_integer(unsigned(commit_rd))) <= commit_value;
            end if;
            rs_value <= read_register(rs_addr);
            rt_value <= read_register(rt_addr);
        end if;
    end process;

end rtl;
