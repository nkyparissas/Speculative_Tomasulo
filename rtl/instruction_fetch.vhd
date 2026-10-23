-- Speculative Tomasulo processor
-- Vibecoded by Nick Kyparissas using Claude Opus 5.5, based on the original
-- Speculative Tomasulo project (see README.md).
--
-- INSTRUCTION_FETCH: program ROM and program counter.
--
-- The fetch unit holds the program in a ROM of ROM_DEPTH words, which is
-- initialised from the text file ROM_FILE during elaboration, and presents
-- the instruction at the current program counter combinationally. The
-- program counter advances whenever a reservation station accepts the
-- presented instruction; otherwise, the same instruction is presented again
-- in the next cycle. As a result, an instruction whose execution unit has no
-- free reservation station stalls the in-order issue, and a word that no unit
-- accepts, such as HALT_WORD, stops instruction fetch permanently. The unit
-- implements no branches. After an exception, the reorder buffer requests a
-- redirect for one cycle, during which no instruction issues, and the
-- program counter then continues at the exception handler, HANDLER_ADDR.
--
-- The ROM file must contain exactly ROM_DEPTH lines, each holding one 19-bit
-- word in binary. This is the file format that Vivado synthesis expects for
-- memory initialisation (UG901), and tools/assembler.py writes it, padding
-- programs with HALT words. In Vivado, the file has to be added to the
-- project, so that synthesis and simulation find it under its plain name.
--
-- Names:
--   ROM_FILE     name of the ROM image
--   HANDLER_ADDR address of the first instruction of the exception handler
--   advance      a reservation station accepted the presented instruction
--   redirect     an exception discards the fetched instructions; fetch
--                continues at HANDLER_ADDR
--   pc           address of the presented instruction
--   instruction  ROM word at address pc

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.tomasulo_pkg.all;

entity instruction_fetch is
    generic (
        ROM_FILE     : string;
        HANDLER_ADDR : natural range 0 to ROM_DEPTH - 1);
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        advance     : in  std_logic;
        redirect    : in  std_logic;
        pc          : out pc_t;
        instruction : out instr_t);
end instruction_fetch;

architecture rtl of instruction_fetch is

    type rom_t is array (ROM_DEPTH - 1 downto 0) of instr_t;

    -- Follows the file-reading template of UG901 (a fixed number of lines,
    -- read as bit_vector), so that Vivado synthesis can initialise the ROM.
    impure function load_rom(file_name : string) return rom_t is
        file     rom_file : text open read_mode is file_name;
        variable rom_line : line;
        variable word     : bit_vector(instr_t'range);
        variable rom      : rom_t;
    begin
        for addr in 0 to ROM_DEPTH - 1 loop
            readline(rom_file, rom_line);
            read(rom_line, word);
            rom(addr) := to_stdlogicvector(word);
        end loop;
        return rom;
    end function load_rom;

    signal rom    : rom_t := load_rom(ROM_FILE);
    signal pc_reg : unsigned(pc_t'range);

begin

    process
    begin
        wait until rising_edge(clk);
        if rst = '1' then
            pc_reg <= (others => '0');
        elsif redirect = '1' then
            pc_reg <= to_unsigned(HANDLER_ADDR, pc_reg'length);
        elsif advance = '1' then
            pc_reg <= pc_reg + 1;
        end if;
    end process;

    instruction <= rom(to_integer(pc_reg));
    pc          <= std_logic_vector(pc_reg);

end rtl;
