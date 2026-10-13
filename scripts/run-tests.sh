#!/usr/bin/env bash
# Test suite (runs inside the Docker image):
#   1. both programs on the unmodified CPU: LED sequence and final 7-segment display
#   2. the original ALU/register testbench (src/simulation/top.v) under Icarus
#   3. Verilator lint of the synthesizable design (errors only)
set -uo pipefail
cd /cpu
LOGS=test-logs; mkdir -p "$LOGS"
pass=0 fail=0
ok()  { echo "PASS  $1"; pass=$((pass + 1)); }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }

program() {  # program <name> <mif> <inputs> <expected LEDs> <expected display>
  local name=$1 mif=$2 inputs=$3 leds=$4 disp=$5
  python3 sim/board.py --log --in "$inputs" "$mif" > "$LOGS/$name.log" 2>&1
  local got_leds got_disp
  got_leds=$(grep -o 'LEDs = *[0-9]*' "$LOGS/$name.log" | awk '{print $3}' | paste -sd' ' -)
  got_disp=$(grep -o 'display SP=[0-9]* PC=[0-9]*' "$LOGS/$name.log")
  if [[ "$got_leds" == "$leds" && "$got_disp" == "display $disp" ]] && grep -q '^  HALT' "$LOGS/$name.log"; then
    ok "$name  (LEDs $got_leds, $got_disp)"
  else
    bad "$name  (LEDs '$got_leds', want '$leds'; '$got_disp', want 'display $disp')"; cat "$LOGS/$name.log"
  fi
}

# mem_init.mif: the expected values are the ones written in the file's own comments
program mem_init       tooling/mem_init.mif      8,9,3 "8 16 7 21"  "SP=63 PC=21"
program mem_init_test  tooling/mem_init_test.mif ""    "5 9 7 2 9"  "SP=63 PC=18"

# Original testbench: exhaustive ALU sweep (2^11 input combinations)
iverilog -o "$LOGS/alu_reg.vvp" src/simulation/top.v src/simulation/modules/*.v 2> "$LOGS/alu_reg.build.log" \
  && vvp -n "$LOGS/alu_reg.vvp" > "$LOGS/alu_reg.log" 2>&1
lines=$(grep -c '^Vreme' "$LOGS/alu_reg.log" 2>/dev/null || echo 0)
wrong=$(awk -F'[=,]' '/^Vreme.*oc = 000/ { a=$4+0; b=$6+0; f=$10+0; if (f != (a+b)%16) n++ } END { print n+0 }' "$LOGS/alu_reg.log")
if [[ $lines -ge 2048 && $wrong -eq 0 ]]; then ok "alu/register testbench  ($lines lines, ADD results checked)"
else bad "alu/register testbench  ($lines lines, $wrong wrong ADD results)"; fi

# Lint: the synthesizable design must elaborate without errors (width warnings are expected)
if verilator --lint-only -Wno-fatal -Wno-lint -Wno-style --top-module top src/synthesis/modules/*.v > "$LOGS/lint.log" 2>&1; then
  ok "verilator lint (top)"
else bad "verilator lint (top)"; cat "$LOGS/lint.log"; fi

echo "---"
echo "$pass passed, $fail failed  (logs: test-logs/)"
[[ $fail -eq 0 ]]
