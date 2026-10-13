#!/usr/bin/env python3
"""Turn the Quartus .mif programs into programs.js for the web board (memory words + listing)."""
import json, os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sim"))
from board import read_mif  # noqa: E402

DESCRIPTIONS = {
    "mem_init.mif": "IN / OUT / MOV / ADD / SUB / MUL. Set the switches when the CPU waits on IN.",
    "mem_init_test.mif": "Constants, indirect addressing ([A]) and STOP showing three values.",
}

programs = []
for path in sys.argv[1:]:
    name = os.path.basename(path)
    comments = {}
    for line in open(path):
        if "--" in line and ":" in line.split("--", 1)[0]:
            addr, rest = line.split(":", 1)
            if addr.strip().isdigit():
                comments[int(addr)] = rest.split("--", 1)[1].strip()
    programs.append({"name": name, "about": DESCRIPTIONS.get(name, ""),
                     "mem": read_mif(path), "comments": comments})
print("export const PROGRAMS = " + json.dumps(programs, indent=1) + ";")
