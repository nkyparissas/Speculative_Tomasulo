#!/usr/bin/env python3
# Speculative Tomasulo processor
# Vibecoded by Nick Kyparissas using Claude Opus 5.5, based on the original
# Speculative Tomasulo project (see README.md).
"""Regression and functional tests for the speculative Tomasulo processor.

Every program in programs/*.asm forms one scenario, and EXCEPTION_SCENARIOS
adds runs of the example program with an exception. For each scenario, the
runner assembles the program with tools/assembler.py, simulates
sim/tb_top_level.vhd with GHDL, converts the VCD into a cycle-level trace
(tests/trace_vcd.py) and performs two checks:

1. Regression: the trace must be identical to tests/golden/<scenario>.trace.
   The golden traces record the cycle-exact behaviour of the original design,
   including its known issues (doc/known_issues.md), so any difference reveals
   a behavioural change.
2. Functional (scenarios without an exception): the register-file writes must
   match the commit sequence of the reference model in tools/assembler.py.
   Programs with a '; @xfail <reason>' directive are expected to fail this
   check until the corresponding issue is fixed.

The run fails on any regression difference, functional failure or unexpected
functional pass. Build products are written to tests/build/.

Usage: tests/run_tests.py [--bless] [--std 93|08] [SCENARIO ...]
"""
import argparse
import difflib
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
sys.path.insert(0, str(REPO / "tests"))
import assembler  # noqa: E402
import trace_vcd  # noqa: E402

BUILD = REPO / "tests" / "build"
GOLDEN = REPO / "tests" / "golden"
SOURCES = sorted((REPO / "rtl").glob("*.vhd")) + [REPO / "sim" / "tb_top_level.vhd"]
TESTBENCH = "tb_top_level"
DEFAULT_CYCLES = 200

# name: (program, exception cycle, ROB tag); see the generics of tb_top_level.
EXCEPTION_SCENARIOS = {
    "example_exception_c6": ("example", 6, 3),
    "example_exception_c7": ("example", 7, 3),  # the original testbench
    "example_exception_c8": ("example", 8, 3),
}


def scenarios():
    """Return {name: (program, exception cycle or None, exception tag)}."""
    result = {p.stem: (p.stem, None, 0) for p in sorted((REPO / "programs").glob("*.asm"))}
    result.update(EXCEPTION_SCENARIOS)
    return result


def ghdl(args, cwd, log):
    with open(log, "a") as f:
        f.write("$ ghdl " + " ".join(args) + "\n")
        f.flush()
        return subprocess.run(["ghdl", *args], cwd=cwd, stdout=f, stderr=subprocess.STDOUT).returncode == 0


def build(build_dir, sources, flags):
    """Analyse the sources and elaborate the testbench; return True on success."""
    work = build_dir / "work"
    work.mkdir(parents=True)
    log = build_dir / "ghdl.log"
    return (ghdl(["-i", *flags, f"--workdir={work}", *map(str, sources)], build_dir, log)
            and ghdl(["-m", *flags, f"--workdir={work}", TESTBENCH], build_dir, log))


def simulate(build_dir, flags, rom, vcd, cycles, exception_cycle, exception_tag):
    generics = [f"-gROM_FILE={rom}", f"-gRUN_CYCLES={cycles}",
                f"-gEXCEPTION_CYCLE={exception_cycle}", f"-gEXCEPTION_ROB_TAG={exception_tag}"]
    return ghdl(["-r", *flags, f"--workdir={build_dir / 'work'}", TESTBENCH, *generics,
                 f"--vcd={vcd}", "--ieee-asserts=disable-at-0"], build_dir, vcd.with_suffix(".log"))


def functional_check(words, directives, writes):
    """Compare the register-file writes against the reference model."""
    expected, _ = assembler.run(words)
    observed = [(rd, value) for _, rd, value in writes]
    if observed == expected:
        status, note = "PASS", f"{len(expected)} commits"
    elif observed == expected[: len(observed)]:
        status, note = "FAIL", f"stalls after {len(observed)} of {len(expected)} commits"
    else:
        n = next((i for i, (o, e) in enumerate(zip(observed, expected)) if o != e), None)
        status = "FAIL"
        note = (f"commit {n} differs from the reference model" if n is not None
                else f"{len(observed)} commits instead of {len(expected)}")
    if "xfail" in directives:
        status = "XFAIL" if status == "FAIL" else "XPASS"
        note += f" (expected to fail: {directives['xfail']})"
    return status, note


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--bless", action="store_true", help="overwrite the golden traces with the current results")
    ap.add_argument("--std", choices=("93", "08"), default="93", help="VHDL standard (default: %(default)s)")
    ap.add_argument("names", nargs="*", metavar="SCENARIO", help="run only these scenarios")
    args = ap.parse_args()

    selected = scenarios()
    unknown = set(args.names) - set(selected)
    if unknown:
        sys.exit(f"unknown scenarios: {', '.join(sorted(unknown))}")
    if args.names:
        selected = {n: s for n, s in selected.items() if n in args.names}
    if shutil.which("ghdl") is None:
        sys.exit("ghdl not found on PATH")

    flags = [f"--std={args.std}"]
    shutil.rmtree(BUILD, ignore_errors=True)
    if not build(BUILD, SOURCES, flags):
        sys.exit(f"GHDL build failed, see {BUILD / 'ghdl.log'}")

    # rtl/rom.data is the default program for Vivado and must stay in sync with its source.
    words, _ = assembler.load_program(str(REPO / "programs" / "example.asm"))
    assembler.write_rom(words, BUILD / "example_reference.data")
    failed = (BUILD / "example_reference.data").read_bytes() != (REPO / "rtl" / "rom.data").read_bytes()
    if failed:
        print("rtl/rom.data does not match programs/example.asm; regenerate it with:\n"
              "  python3 tools/assembler.py programs/example.asm -o rtl/rom.data")

    for name, (program, exception_cycle, exception_tag) in selected.items():
        words, directives = assembler.load_program(str(REPO / "programs" / f"{program}.asm"))
        rom, vcd = BUILD / f"{name}.data", BUILD / f"{name}.vcd"
        assembler.write_rom(words, rom)
        cycles = int(directives.get("cycles", DEFAULT_CYCLES))
        if not simulate(BUILD, flags, rom, vcd, cycles,
                        -1 if exception_cycle is None else exception_cycle, exception_tag):
            print(f"{name:24s} ERROR       simulation failed, see {vcd.with_suffix('.log')}")
            failed = True
            continue
        text, writes = trace_vcd.trace(vcd)
        (BUILD / f"{name}.trace").write_text(text)

        golden = GOLDEN / f"{name}.trace"
        if args.bless:
            GOLDEN.mkdir(exist_ok=True)
            golden.write_text(text)
            regression = "BLESSED"
        elif not golden.exists():
            regression = "MISSING"
        elif golden.read_text() == text:
            regression = "PASS"
        else:
            regression = "FAIL"
            diff = difflib.unified_diff(golden.read_text().splitlines(True), text.splitlines(True),
                                        str(golden), str(BUILD / f"{name}.trace"))
            (BUILD / f"{name}.diff").write_text("".join(diff))

        if exception_cycle is None:
            functional, note = functional_check(words, directives, writes)
        else:
            functional, note = "-", f"exception at ROB tag {exception_tag} on cycle {exception_cycle}"
        failed |= regression in ("FAIL", "MISSING") or functional in ("FAIL", "XPASS")
        print(f"{name:24s} regression {regression:8s} functional {functional:6s} {note}")

    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
