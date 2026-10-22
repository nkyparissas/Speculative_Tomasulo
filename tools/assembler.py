#!/usr/bin/env python3
# Speculative Tomasulo processor
# Vibecoded by Nick Kyparissas using Claude Opus 5.5, based on the original
# Speculative Tomasulo project (see README.md).
"""Assembler, disassembler and reference model for the Speculative Tomasulo ISA.

The processor executes the small custom instruction set of the original
Speculative Tomasulo project: 19-bit words with a 2-bit execution-unit class,
a 2-bit function code and three 5-bit register fields (rd, rs, rt), loosely
modelled on the MIPS R-type format. There are no immediates, loads, stores or
branches; registers r0..r10 start with their own index after reset, which is
the only way to obtain input values.

    18 17 | 16 15 | 14 .. 10 | 9 .. 5 | 4 .. 0
    class | fop   |    rd    |   rs   |   rt

Assembly syntax (one instruction per line, ';' starts a comment):

    OR   rd, rs, rt      rd = rs | rt           (class 00, fop 00)
    AND  rd, rs, rt      rd = rs & rt           (class 00, fop 01)
    NOT  rd, rs [, rt]   rd = ~rs               (class 00, fop 10)
    ADD  rd, rs, rt      rd = rs + rt           (class 01, fop 00)
    SUB  rd, rs, rt      rd = rs - rt           (class 01, fop 01)
    SLL  rd, rs [, rt]   rd = rs << 1           (class 01, fop 10)
    HALT                 stops instruction fetch (all ones)
    .word VALUE          raw 19-bit word (0b..., 0x... or decimal)

The hardware tracks rt as a source operand even for NOT and SLL. Hence, the
assembler sets rt = rs when the third operand is omitted, which introduces no
extra dependency; an explicit rt reproduces legacy encodings.

Comment lines of the form '; @key value' are directives for the test runner
(tests/run_tests.py), e.g. '; @cycles 300' or '; @xfail <reason>'.

Usage:
    assembler.py PROGRAM.asm [-o ROM.data]   assemble into a ROM image
    assembler.py --disassemble ROM.data      list the instructions of a ROM image
    assembler.py --run PROGRAM.asm|ROM.data  print the reference model's results
"""
import argparse
import re
import sys

WORD_BITS = 19
ROM_DEPTH = 1024  # must match ROM_DEPTH in rtl/tomasulo_pkg.vhd
NUM_REGS = 32
DATA_MASK = 0xFFFFFFFF
HALT_WORD = (1 << WORD_BITS) - 1

CLASS_LOGICAL = 0b00
CLASS_ARITHMETIC = 0b01

# mnemonic: (class, fop, unary)
OPCODES = {
    "OR": (CLASS_LOGICAL, 0b00, False),
    "AND": (CLASS_LOGICAL, 0b01, False),
    "NOT": (CLASS_LOGICAL, 0b10, True),
    "ADD": (CLASS_ARITHMETIC, 0b00, False),
    "SUB": (CLASS_ARITHMETIC, 0b01, False),
    "SLL": (CLASS_ARITHMETIC, 0b10, True),
}
MNEMONICS = {(c, f): m for m, (c, f, _) in OPCODES.items()}


class AsmError(Exception):
    pass


def encode(cls, fop, rd, rs, rt):
    return cls << 17 | fop << 15 | rd << 10 | rs << 5 | rt


def decode(word):
    """Split a word into (class, fop, rd, rs, rt)."""
    return (word >> 17) & 3, (word >> 15) & 3, (word >> 10) & 31, (word >> 5) & 31, word & 31


def parse_register(token, where):
    m = re.fullmatch(r"[rR](\d+)", token)
    if not m or int(m.group(1)) >= NUM_REGS:
        raise AsmError(f"{where}: invalid register '{token}' (expected r0..r{NUM_REGS - 1})")
    return int(m.group(1))


def parse_word(token, where):
    try:
        value = int(token, 0)
    except ValueError:
        raise AsmError(f"{where}: invalid value '{token}'") from None
    if not 0 <= value <= HALT_WORD:
        raise AsmError(f"{where}: value '{token}' does not fit in {WORD_BITS} bits")
    return value


def assemble(text, name="<input>"):
    """Return (words, directives) for an assembly source text."""
    words, directives = [], {}
    for number, raw in enumerate(text.splitlines(), start=1):
        where = f"{name}:{number}"
        code, _, comment = raw.partition(";")
        directive = re.match(r"\s*@(\w+)\s*(.*?)\s*$", comment)
        if not code.strip() and directive:
            directives[directive.group(1)] = directive.group(2)
        tokens = code.replace(",", " ").split()
        if not tokens:
            continue
        op, args = tokens[0].upper(), tokens[1:]
        if op == "HALT" and not args:
            words.append(HALT_WORD)
        elif op == ".WORD" and len(args) == 1:
            words.append(parse_word(args[0], where))
        elif op in OPCODES:
            cls, fop, unary = OPCODES[op]
            if len(args) == 3 or (unary and len(args) == 2):
                rd, rs, *rt = (parse_register(a, where) for a in args)
                words.append(encode(cls, fop, rd, rs, rt[0] if rt else rs))
            else:
                form = f"{op} rd, rs" + (" [, rt]" if unary else ", rt")
                raise AsmError(f"{where}: expected '{form}'")
        else:
            raise AsmError(f"{where}: unknown instruction '{raw.strip()}'")
    if len(words) > ROM_DEPTH:
        raise AsmError(f"{name}: {len(words)} words do not fit in a {ROM_DEPTH}-word ROM")
    return words, directives


def disassemble(word):
    cls, fop, rd, rs, rt = decode(word)
    if cls not in (CLASS_LOGICAL, CLASS_ARITHMETIC):
        return "HALT" if word == HALT_WORD else f".word 0b{word:0{WORD_BITS}b}  ; halts fetch"
    if (cls, fop) not in MNEMONICS:
        return f".word 0b{word:0{WORD_BITS}b}  ; fop 11 yields zero"
    mnemonic = MNEMONICS[(cls, fop)]
    if OPCODES[mnemonic][2]:
        return f"{mnemonic} r{rd}, r{rs}" + ("" if rt == rs else f", r{rt}")
    return f"{mnemonic} r{rd}, r{rs}, r{rt}"


def write_rom(words, path):
    """Write a ROM image: one binary word per line, padded with HALT to ROM_DEPTH lines."""
    padded = list(words) + [HALT_WORD] * (ROM_DEPTH - len(words))
    with open(path, "w", newline="\n") as f:
        f.writelines(f"{w:0{WORD_BITS}b}\n" for w in padded)


def read_rom(path):
    with open(path) as f:
        return [int(line.strip(), 2) for line in f if line.strip()]


def initial_registers():
    """Register file contents after reset (see REGISTER_FILE in the RTL)."""
    return [r if r <= 10 else 0 for r in range(NUM_REGS)]


def alu(cls, fop, a, b):
    if cls == CLASS_LOGICAL:
        result = (a | b, a & b, ~a, 0)[fop]
    else:
        result = (a + b, a - b, a << 1, 0)[fop]
    return result & DATA_MASK


def run(words, max_instructions=16 * ROM_DEPTH):
    """Execute in program order until HALT; return (commits, registers).

    commits lists (rd, value) per retired instruction. Fetch stalls on the first
    word whose class is neither logical nor arithmetic; the 10-bit PC wraps
    around at the end of the ROM, exactly as in the hardware.
    """
    regs, commits, pc = initial_registers(), [], 0
    for _ in range(max_instructions):
        word = words[pc] if pc < len(words) else HALT_WORD
        cls, fop, rd, rs, rt = decode(word)
        if cls not in (CLASS_LOGICAL, CLASS_ARITHMETIC):
            break
        regs[rd] = alu(cls, fop, regs[rs], regs[rt])
        commits.append((rd, regs[rd]))
        pc = (pc + 1) % ROM_DEPTH
    return commits, regs


def load_program(path):
    """Return (words, directives) from an assembly source or a ROM image."""
    with open(path) as f:
        text = f.read()
    if path.endswith(".asm"):
        return assemble(text, path)
    return read_rom(path), {}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    group = ap.add_mutually_exclusive_group()
    group.add_argument("--disassemble", action="store_true", help="list the instructions of a ROM image")
    group.add_argument("--run", action="store_true", help="run the reference model and print the results")
    ap.add_argument("-o", "--output", help="ROM image to write (default: PROGRAM with .data suffix)")
    ap.add_argument("program", help="assembly source (.asm) or ROM image")
    args = ap.parse_args()
    try:
        words, _ = load_program(args.program)
    except (AsmError, OSError, ValueError) as e:
        sys.exit(f"error: {e}")
    if args.disassemble:
        last = max((i for i, w in enumerate(words) if w != HALT_WORD), default=-1)
        for addr, word in enumerate(words[: last + 2]):
            print(f"{addr:4d}  {word:0{WORD_BITS}b}  {disassemble(word)}")
        if last + 2 < len(words):
            print(f"      (addresses {last + 2}..{len(words) - 1} hold HALT)")
    elif args.run:
        commits, regs = run(words)
        for n, (rd, value) in enumerate(commits):
            print(f"commit {n:3d}: r{rd} <= {value:08x}")
        changed = [r for r in range(NUM_REGS) if regs[r] != initial_registers()[r]]
        print("final registers (changed): " + (", ".join(f"r{r}={regs[r]:08x}" for r in changed) or "none"))
    else:
        out = args.output or re.sub(r"\.asm$", "", args.program) + ".data"
        write_rom(words, out)
        print(f"{args.program}: {len(words)} words -> {out}")


if __name__ == "__main__":
    main()
