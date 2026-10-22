#!/usr/bin/env python3
# Speculative Tomasulo processor
# Vibecoded by Nick Kyparissas using Claude Opus 5.5, based on the original
# Speculative Tomasulo project (see README.md).
"""Cycle-level trace of the processor from a GHDL VCD file.

The signals in COLUMNS are sampled at every falling clock edge, i.e. in the
settled state produced by the preceding rising edge. Row k therefore shows the
state after cycle k (rising edge k, at (k + 1) * 10 ns in tb_top_level). The
testbench changes its stimulus at the same time as rising edges, so sampling
just before an edge would misreport what the flip-flops actually see.

Rows at the end of the run that are identical to their predecessor (apart from
the cycle number) are collapsed into a single line, since a drained or
deadlocked processor no longer changes state. After the table, the trace lists
the register-file writes and the register contents reconstructed from them.

Usage: trace_vcd.py [--top tb_top_level] FILE.vcd
"""
import argparse
import sys

# Header: (scope relative to the testbench, VCD variable, format). Update the
# paths in the same step as any change that renames these signals.
COLUMNS = {
    "rst": ("dut", "rst", "raw"),
    "pc": ("dut", "pc[9:0]", "dec"),
    "instruction": ("dut", "instruction[18:0]", "raw"),
    "ackA": ("dut", "ack_arithmetic", "raw"),
    "ackL": ("dut", "ack_logical", "raw"),
    "head": ("dut.u_rob", "head[3:0]", "dec"),
    "tail": ("dut", "rob_tail[3:0]", "dec"),
    "rsTag": ("dut", "rob_rs_tag[3:0]", "hex"),
    "rtTag": ("dut", "rob_rt_tag[3:0]", "hex"),
    "reqA": ("dut", "cdb_req_arithmetic", "raw"),
    "reqL": ("dut", "cdb_req_logical", "raw"),
    "grant": ("dut", "cdb_grant[1:0]", "raw"),
    "cdbTag": ("dut", "cdb_tag[3:0]", "hex"),
    "cdbValue": ("dut", "cdb_value[31:0]", "hex"),
    "we": ("dut", "commit_we", "raw"),
    "rd": ("dut", "commit_rd[4:0]", "dec"),
    "commitValue": ("dut", "commit_value[31:0]", "hex"),
    "exc": ("dut", "exception_flag", "raw"),
    "flush": ("dut", "flush_tag[3:0]", "hex"),
    "excPC": ("dut", "exception_pc[9:0]", "dec"),
}
CLOCK = ("", "clk")

# REGISTER_FILE reset contents: r0..r10 hold their own index, the rest are zero.
RF_RESET = [r if r <= 10 else 0 for r in range(32)]


def parse_vcd(path, top):
    """Return [(time, {header: value})] for the clock and every column."""
    wanted = {(scope, var): header for header, (scope, var, _) in COLUMNS.items()}
    wanted[CLOCK] = "clk"
    ids, scope = {}, []
    changes, batch, t = [], {}, 0
    with open(path) as f:
        lines = iter(f)
        for line in lines:
            tok = line.split()
            if not tok:
                continue
            if tok[0] == "$scope":
                scope.append(tok[2])
            elif tok[0] == "$upscope":
                scope.pop()
            elif tok[0] == "$var" and scope and scope[0] == top:
                var = tok[4] + (tok[5] if tok[5] != "$end" else "")
                key = (".".join(scope[1:]), var)
                if key in wanted:
                    ids.setdefault(tok[3], []).append(wanted[key])
            elif tok[0] == "$enddefinitions":
                break
        for line in lines:
            line = line.strip()
            if not line or line[0] == "$":
                continue
            if line[0] == "#":
                if batch:
                    changes.append((t, batch))
                t, batch = int(line[1:]), {}
                continue
            if line[0] in "bB":
                value, ident = line[1:].split()
            else:
                value, ident = line[0], line[1:]
            for name in ids.get(ident, []):
                batch[name] = value
        if batch:
            changes.append((t, batch))
    missing = set(wanted.values()) - {n for names in ids.values() for n in names}
    if missing:
        raise ValueError(f"{path}: signals not found under '{top}': {sorted(missing)}")
    return changes


def to_int(bits):
    return int(bits, 2) if bits and set(bits) <= {"0", "1"} else None


def render(bits, fmt):
    value = to_int(bits)
    if fmt == "raw" or value is None:
        return bits
    if fmt == "dec":
        return str(value)
    return f"{value:0{(len(bits) + 3) // 4}x}"


def trace(vcd_path, top="tb_top_level"):
    """Return (text, writes), where writes lists (cycle, rd, value) per RF write."""
    state, rows, writes = {}, [], []
    rf = list(RF_RESET)
    prev_clk, cycle = None, -1
    for _, batch in parse_vcd(vcd_path, top):
        clk = batch.get("clk")
        if clk == "1" and prev_clk == "0":
            cycle += 1
        state.update(batch)
        if clk == "0" and prev_clk == "1" and cycle >= 0:
            rows.append([render(state[h], fmt) for h, (_, _, fmt) in COLUMNS.items()])
            # The register file performs this write on the next rising edge.
            if state["rst"] == "0" and state["we"] == "1":
                rd, value = to_int(state["rd"]), to_int(state["commitValue"])
                rf[rd] = value
                writes.append((cycle + 1, rd, value))
        if clk is not None:
            prev_clk = clk

    last = len(rows) - 1
    while last > 0 and rows[last] == rows[last - 1]:
        last -= 1
    header = ["cycle"] + list(COLUMNS)
    table = [[str(c)] + row for c, row in enumerate(rows[: last + 1])]
    widths = [max(len(r[i]) for r in table + [header]) for i in range(len(header))]
    out = [" ".join(cell.rjust(w) for cell, w in zip(r, widths)) for r in [header] + table]
    if last < len(rows) - 1:
        out.append(f"(cycles {last + 1}..{len(rows) - 1} are identical to cycle {last})")
    out.append("\nRegister-file writes (cycle, register, value):")
    out += [f"  {c:4d}  r{rd:<2} <= {value:08x}" for c, rd, value in writes] or ["  none"]
    out.append("\nRegister file after the last cycle:")
    for base in range(0, 32, 8):
        out.append(f"  r{base:<2}..r{base + 7:<2}: " + " ".join(f"{rf[r]:08x}" for r in range(base, base + 8)))
    return "\n".join(out) + "\n", writes


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--top", default="tb_top_level", help="testbench entity (default: %(default)s)")
    ap.add_argument("vcd")
    args = ap.parse_args()
    try:
        text, _ = trace(args.vcd, args.top.lower())
    except (OSError, ValueError) as e:
        sys.exit(f"error: {e}")
    sys.stdout.write(text)


if __name__ == "__main__":
    main()
