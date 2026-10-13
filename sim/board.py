#!/usr/bin/env python3
"""Run the CPU on a virtual DE0 board (Icarus Verilog) and show what the real board showed.

    board.py [--log | --frames] [--in 8,9,3] [--delay 0.12] program.mif

  --frames  animated board: 7-segment PC/SP, LEDs, switches, CPU state (default on a terminal)
  --log     one line per executed instruction plus every LED change (used by the tests)
  --in      values the operator sets on SW3..SW0, one per IN instruction (0..15)

Everything shown comes from the simulated hardware: the digits are decoded from the real
segment outputs of ssd.v, the LEDs are the led[] port, the registers are memory words 1..7.
"""
import argparse, os, re, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
VVP = os.environ.get("BOARD_VVP", os.path.join(HERE, "..", "build", "board.vvp"))

STATES = {
    0: "halt", 1: "fetch1", 2: "fetch2", 3: "fetch3", 4: "decode", 5: "execute_in",
    6: "execute_out", 7: "execute_out_indirect", 8: "execute_stop_1", 9: "execute_stop_1_indirect",
    10: "execute_stop_2", 11: "execute_stop_2_indirect", 12: "execute_stop_3",
    13: "execute_stop_3_indirect", 14: "execute_mov", 15: "execute_mov_indirect_2",
    16: "execute_mov_indirect_1", 17: "execute_mov_constant", 18: "decode_arithmetic_1_indirect",
    19: "decode_arithmetic_2_indirect", 20: "decode_arithmetic_3", 21: "decode_arithmetic_3_indirect",
    22: "execute_arithmetic", 23: "prefetch",
}
REG = "-ABCDEFG"   # operand address 1..7 = A..G (0 means "no operand")


# ---------------------------------------------------------------- .mif -> memory words
def read_mif(path, depth=64):
    text = open(path).read()
    body = text.split("CONTENT BEGIN", 1)[1].split("END;", 1)[0]
    mem = [0] * depth
    for line in body.splitlines():
        line = line.split("--", 1)[0].strip()
        m = re.match(r"\[?(\d+)(?:\.\.(\d+))?\]?\s*:\s*([0-9A-Fa-f]+)\s*;", line)
        if m:
            lo, hi = int(m[1]), int(m[2] or m[1])
            for a in range(lo, hi + 1):
                mem[a] = int(m[3], 16)
    return mem


# ---------------------------------------------------------------- disassembler
def operand(field):
    """4-bit operand field: bit 3 = indirect, bits 2..0 = address (A..G)."""
    name = REG[field & 7]
    return f"[{name}]" if field & 8 else name


def disasm(hi, lo=None):
    op, f1, f2, f3 = hi >> 12, (hi >> 8) & 15, (hi >> 4) & 15, hi & 15
    if op == 0:
        if f3 == 8:
            return f"MOV {operand(f1)}, {lo if lo is not None else '#imm'}"
        return f"MOV {operand(f1)}, {operand(f2)}"
    if op in (1, 2, 3, 4):
        return f"{['', 'ADD', 'SUB', 'MUL', 'DIV'][op]} {operand(f1)}, {operand(f2)}, {operand(f3)}"
    if op == 7:
        return f"IN {operand(f1)}"
    if op == 8:
        return f"OUT {operand(f1)}"
    if op == 15:
        ops = [operand(f) for f in (f1, f2, f3) if f]
        return "STOP" + (" " + ", ".join(ops) if ops else "")
    return f"??? ({hi:04x})"


# ---------------------------------------------------------------- simulation
def simulate(mem, inputs, maxcyc=2000):
    with tempfile.TemporaryDirectory() as tmp:
        memf, inf = os.path.join(tmp, "mem.hex"), os.path.join(tmp, "in.hex")
        open(memf, "w").write("\n".join(f"{w:04x}" for w in mem) + "\n")
        open(inf, "w").write("\n".join(f"{v:x}" for v in inputs) + "\n")
        out = subprocess.run(["vvp", "-n", VVP, f"+mem={memf}", f"+in={inf}", f"+maxcyc={maxcyc}"],
                             capture_output=True, text=True, check=True).stdout
    trace = []
    for line in out.splitlines():
        if not line.startswith("T "):
            continue
        f = line.split()
        trace.append(dict(
            cyc=int(f[1]), state=int(f[2]), pc=int(f[3]), sp=int(f[4]),
            ir=int(f[5], 16), irl=int(f[6], 16), led=int(f[7], 16), sw=int(f[8], 16),
            hex=int(f[9], 16), regs=[int(x, 16) for x in f[10:17]], we=int(f[17]), addr=int(f[18])))
    return trace


# ---------------------------------------------------------------- 7-segment rendering
def seg_lines(bits7):
    """ssd.v drives active-low segments a..g on bits 0..6; draw them as 3 text rows."""
    on = [not (bits7 >> i) & 1 for i in range(7)]   # a b c d e f g
    a, b, c, d, e, f, g = on
    return [" " + ("_" if a else " ") + " ",
            ("|" if f else " ") + ("_" if g else " ") + ("|" if b else " "),
            ("|" if e else " ") + ("_" if d else " ") + ("|" if c else " ")]


def display(hexbits):
    # top.v: hex = {SP tens, SP ones, PC tens, PC ones}, 7 bits each
    digits = [(hexbits >> s) & 0x7F for s in (21, 14, 7, 0)]
    rows = [seg_lines(d) for d in digits]
    return ["  ".join(r[i] for r in rows[:2]) + "      " + "  ".join(r[i] for r in rows[2:])
            for i in range(3)]


def frame(t, step_text, out_hist):
    led, sw = t["led"], t["sw"]
    leds = " ".join("●" if (led >> i) & 1 else "○" for i in range(9, -1, -1))
    sws = " ".join("▀" if (sw >> i) & 1 else "▄" for i in range(9, -1, -1))
    regs = "  ".join(f"{REG[i + 1]}={v}" for i, v in enumerate(t["regs"]))
    width = 66
    body = [
        "",
        "    SP           PC",
        *["  " + row for row in display(t["hex"])],
        "  HEX3 HEX2     HEX1 HEX0",
        "",
        f"  LEDG  {leds}    OUT = {led} ({led:05b})",
        f"  SW    {sws}    SW9 = {'run' if sw >> 9 & 1 else 'RESET'}, SW3-0 = {sw & 15}",
        "        9 8 7 6 5 4 3 2 1 0",
        "",
    ]
    title = " Terasic DE0 · Cyclone III "
    return [
        "┌" + title.center(width + 2, "─") + "┐",
        *["│ " + line.ljust(width) + " │" for line in body],
        "└" + "─" * (width + 2) + "┘",
        f"  CPU clock {t['cyc']:3d}   state {STATES.get(t['state'], t['state'])}",
        f"  IR {t['ir']:04x}  {disasm(t['ir'], t['irl']):<26}{step_text}",
        f"  {regs}",
        f"  LED history: {' → '.join(map(str, out_hist)) or '-'}",
    ]


# ---------------------------------------------------------------- views
OUTPUT_STATES = (6, 8, 10, 12)   # execute_out, execute_stop_1..3: LEDs change on the next clock
DIGIT = {0x40: 0, 0x79: 1, 0x24: 2, 0x30: 3, 0x19: 4, 0x12: 5, 0x02: 6, 0x78: 7, 0x00: 8, 0x10: 9}


def shown_digits(hexbits):
    return "".join(str(DIGIT.get((hexbits >> s) & 0x7F, "?")) for s in (21, 14, 7, 0))


def instr_pc(t):
    two_words = (t["ir"] >> 12) == 0 and (t["ir"] & 15) == 8
    return t["pc"] - (2 if two_words else 1)


def run_log(trace):
    for i, t in enumerate(trace):
        if i and trace[i - 1]["state"] in OUTPUT_STATES:
            print(f"        LEDs = {t['led']:2d}  ({t['led']:05b})")
        if t["state"] == 4:   # decode: the instruction is in IR
            # the switches are sampled at the end of this clock, so show the next line's value
            sampled = trace[min(i + 1, len(trace) - 1)]["sw"] & 15
            note = f"   <- switches SW3-0 = {sampled}" if t["ir"] >> 12 == 7 else ""
            print(f"  {instr_pc(t):2d}: {t['ir']:04x}  {disasm(t['ir'], t['irl'])}{note}")
    last = trace[-1]
    d = shown_digits(last["hex"])
    print(f"  {'HALT' if last['state'] == 0 else 'STOPPED (cycle limit)'} after {last['cyc']} CPU clocks;"
          f" display SP={d[:2]} PC={d[2:]}")


def run_frames(trace, delay):
    out_hist = []
    sys.stdout.write("\033[2J")
    for prev, t in zip([None] + trace, trace):
        if prev and prev["state"] in OUTPUT_STATES:
            out_hist.append(t["led"])
        step = f"writes mem[{t['addr']}]" if t["we"] else ""
        sys.stdout.write("\033[H" + "\n".join(frame(t, step, out_hist)) + "\033[J\n")
        sys.stdout.flush()
        time.sleep(delay * (4 if t["state"] == 4 else 1))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("program", help="Quartus .mif memory image")
    ap.add_argument("--in", dest="inputs", default="", help="comma-separated switch values for IN")
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--log", action="store_true")
    mode.add_argument("--frames", action="store_true")
    ap.add_argument("--delay", type=float, default=0.12, help="seconds per CPU clock in --frames")
    ap.add_argument("--maxcyc", type=int, default=2000)
    args = ap.parse_args()

    inputs = [int(x) for x in args.inputs.split(",") if x.strip()]
    if any(not 0 <= v <= 15 for v in inputs):
        ap.error("--in values must be 0..15 (SW3..SW0)")
    mem = read_mif(args.program)
    trace = simulate(mem, inputs, args.maxcyc)
    if args.frames or (not args.log and sys.stdout.isatty()):
        run_frames(trace, args.delay)
    else:
        run_log(trace)


if __name__ == "__main__":
    main()
