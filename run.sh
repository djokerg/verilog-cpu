#!/usr/bin/env bash
# One-command entry point. Needs only Docker.
#
#   ./run.sh                     animated DE0 board running tooling/mem_init.mif (inputs 8, 9, 3)
#   ./run.sh test-prog           the other program, tooling/mem_init_test.mif
#   ./run.sh my.mif --in 5,2     any .mif program; --in sets SW3-0 for each IN instruction
#   ./run.sh ... --log           instruction trace instead of the animation
#   ./run.sh ... --delay 0.5     seconds per CPU clock in the animation (real board: 1.0)
#   ./run.sh test                test suite
#   ./run.sh web                 build the browser board and serve it on http://localhost:8000
#   ./run.sh shell               shell with iverilog / verilator / yosys
set -euo pipefail
cd "$(dirname "$0")"

SIM=verilog-cpu-sim
build_sim() { echo "Building the simulator image (first run takes a minute)..." >&2
              docker build -q --target sim -t "$SIM" . >/dev/null; }
tty=(-i); [[ -t 0 && -t 1 ]] && tty=(-it)

case "${1:-demo}" in
  demo|test-prog|-[a-z-]*)
    prog=tooling/mem_init.mif; inputs=(--in 8,9,3)
    [[ "${1:-}" == test-prog ]] && { prog=tooling/mem_init_test.mif; inputs=(); }
    [[ "${1:-}" == demo || "${1:-}" == test-prog ]] && shift
    [[ " $* " == *" --in "* ]] && inputs=()
    build_sim
    docker run --rm "${tty[@]}" "$SIM" ${inputs[@]+"${inputs[@]}"} "$@" "$prog" ;;
  test)
    build_sim
    mkdir -p test-logs
    docker run --rm -v "$PWD/test-logs:/cpu/test-logs" --entrypoint /cpu/scripts/run-tests.sh "$SIM" ;;
  web)
    echo "Building the WebAssembly board (first run takes several minutes)..." >&2
    docker build -q --target web -t verilog-cpu-web . >/dev/null
    echo "Open http://localhost:8000  (Ctrl-C to stop)" >&2
    docker run --rm -it -p 8000:8000 verilog-cpu-web ;;
  shell)
    build_sim
    docker run --rm "${tty[@]}" -v "$PWD:/work" -w /work --entrypoint bash "$SIM" ;;
  *.mif)
    [[ -f "$1" ]] || { echo "run.sh: no such file: $1" >&2; exit 1; }
    dir=$(cd "$(dirname "$1")" && pwd); file=$(basename "$1"); shift
    build_sim
    docker run --rm "${tty[@]}" -v "$dir:/input:ro" "$SIM" "$@" "/input/$file" ;;
  *)
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
