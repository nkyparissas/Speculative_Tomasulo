-- Speculative Tomasulo processor
-- Vibecoded by Nick Kyparissas using Claude Opus 5.5, based on the original
-- Speculative Tomasulo project (see README.md).
--
-- TOMASULO_PKG: definitions shared by all modules of the processor.
--
-- This package defines the instruction format, the data types of the data
-- path, the codes that the modules exchange and the operations of the two
-- execution units. Keeping these definitions in one place replaces the bit
-- offsets and literal codes that each module would otherwise repeat, and it
-- allows the reservation stations and functional units to be described once
-- and instantiated per execution unit.
--
-- An instruction occupies 19 bits: a 2-bit execution unit, a 2-bit function
-- code (fop) and three 5-bit register addresses (rd, rs, rt). The register
-- file holds 32 registers of 32 bits, and the reorder buffer (ROB) holds 15
-- entries. The index of a ROB entry doubles as the tag that names the result
-- of the instruction in that entry; hence, tags range from 0 to 14, and the
-- remaining 4-bit value, TAG_NONE, denotes the absence of a tag (an operand
-- that is already available, an idle bus or an empty pipeline stage).
--
-- The unit codes UNIT_LOGICAL and UNIT_ARITHMETIC appear in the instruction
-- and also identify the owner of the common data bus (CDB), whose arbiter
-- grants the bus to one unit per cycle. An instruction with any other unit
-- code ("10" or "11") is accepted by no execution unit and therefore stalls
-- instruction fetch for good, which programs use as a HALT instruction.
--
-- Names:
--   word_t           32-bit data word (register and operand values)
--   reg_addr_t       register address
--   pc_t             program counter, i.e. ROM address
--   instr_t          instruction word
--   tag_t            ROB entry index used as a result tag
--   unit_t, fop_t    execution unit and function code of an instruction
--   *_FIELD          bit ranges of the instruction fields
--   GRANT_NONE       CDB grant value when no unit owns the bus
--   HALT_WORD        canonical HALT instruction (all ones)
--   execute          result of an operation, i.e. the behaviour of both ALUs
--   in_flush_range   whether a flush discards the instruction with a given tag
--   operation_t      operation dispatched to a functional unit
--   rs_entry_t       contents of one reservation station
--   rob_entry_t      contents of one ROB entry

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package tomasulo_pkg is

    subtype word_t     is std_logic_vector(31 downto 0);
    subtype reg_addr_t is std_logic_vector(4 downto 0);
    subtype pc_t       is std_logic_vector(9 downto 0);
    subtype instr_t    is std_logic_vector(18 downto 0);
    subtype tag_t      is std_logic_vector(3 downto 0);
    subtype unit_t     is std_logic_vector(1 downto 0);
    subtype fop_t      is std_logic_vector(1 downto 0);

    constant ROM_DEPTH : positive := 1024;
    constant NUM_REGS  : positive := 32;
    constant ROB_SIZE  : positive := 15;

    -- Instruction fields: unit | fop | rd | rs | rt.
    subtype UNIT_FIELD   is natural range 18 downto 17;
    subtype FOP_FIELD    is natural range 16 downto 15;
    subtype RD_FIELD     is natural range 14 downto 10;
    subtype RS_FIELD     is natural range 9 downto 5;
    subtype RT_FIELD     is natural range 4 downto 0;

    constant UNIT_LOGICAL    : unit_t  := "00";
    constant UNIT_ARITHMETIC : unit_t  := "01";
    constant GRANT_NONE      : unit_t  := "11";
    constant TAG_NONE        : tag_t   := "1111";
    constant HALT_WORD       : instr_t := (others => '1');

    -- Operations: logical unit OR, AND, NOT rs; arithmetic unit ADD, SUB,
    -- rs shifted left by one. Function code "11" yields zero in both units.
    function execute(unit : unit_t; fop : fop_t; a, b : word_t) return word_t;

    -- Operation dispatched from a reservation station to its functional unit.
    -- The tag is TAG_NONE in cycles without a dispatch.
    type operation_t is record
        tag  : tag_t;
        fop  : fop_t;
        a, b : word_t;
    end record;

    constant OPERATION_NONE : operation_t := (
        tag => TAG_NONE,
        fop => (others => '0'),
        a   => (others => '0'),
        b   => (others => '0'));

    -- A source operand is available when its q field equals TAG_NONE, in
    -- which case v holds its value; otherwise, q names the ROB entry that
    -- will produce it.
    type rs_entry_t is record
        busy : std_logic;   -- the station holds an instruction
        fop  : fop_t;
        tag  : tag_t;       -- ROB entry of the instruction itself
        v1   : word_t;      -- operand rs
        q1   : tag_t;
        v2   : word_t;      -- operand rt
        q2   : tag_t;
    end record;

    -- A released station holds all zeros, so its q fields read as tag 0 and
    -- the station cannot dispatch before its operands have been filled in.
    constant RS_ENTRY_EMPTY : rs_entry_t := (
        busy => '0',
        fop  => (others => '0'),
        tag  => (others => '0'),
        v1   => (others => '0'),
        q1   => (others => '0'),
        v2   => (others => '0'),
        q2   => (others => '0'));

    type rob_entry_t is record
        busy  : std_logic;   -- the entry holds an instruction
        pc    : pc_t;        -- reported when the instruction faults
        rd    : reg_addr_t;  -- destination register
        value : word_t;      -- result, valid when done = '1'
        done  : std_logic;   -- the result has been broadcast
    end record;

    constant ROB_ENTRY_EMPTY : rob_entry_t := (
        busy  => '0',
        pc    => (others => '0'),
        rd    => (others => '0'),
        value => (others => '0'),
        done  => '0');

    -- True if a flush that starts at flush_tag discards the instruction with
    -- this tag, i.e. if the tag lies in the circular range from flush_tag up
    -- to, but excluding, the ROB tail. If flush_tag equals the tail, the range
    -- covers every tag, which happens when an exception names the head of a
    -- full buffer. Without a flush (flush_tag = TAG_NONE) or an instruction
    -- (tag = TAG_NONE), the result is false. The ROB uses the function in the
    -- exception cycle, and the reservation stations and the functional units
    -- in the cycle after.
    function in_flush_range(tag, flush_tag, tail : tag_t) return boolean;

end package tomasulo_pkg;

package body tomasulo_pkg is

    function execute(unit : unit_t; fop : fop_t; a, b : word_t) return word_t is
    begin
        if unit = UNIT_ARITHMETIC then
            case fop is
                when "00"   => return std_logic_vector(unsigned(a) + unsigned(b));
                when "01"   => return std_logic_vector(unsigned(a) - unsigned(b));
                when "10"   => return std_logic_vector(shift_left(unsigned(a), 1));
                when others => return (others => '0');
            end case;
        else
            case fop is
                when "00"   => return a or b;
                when "01"   => return a and b;
                when "10"   => return not a;
                when others => return (others => '0');
            end case;
        end if;
    end function execute;

    function in_flush_range(tag, flush_tag, tail : tag_t) return boolean is
        constant t     : integer := to_integer(unsigned(tag));
        constant first : integer := to_integer(unsigned(flush_tag));
        constant stop  : integer := to_integer(unsigned(tail));
    begin
        if tag = TAG_NONE or flush_tag = TAG_NONE then
            return false;
        elsif first < stop then
            return t >= first and t < stop;
        else
            return t >= first or t < stop;
        end if;
    end function in_flush_range;

end package body tomasulo_pkg;
