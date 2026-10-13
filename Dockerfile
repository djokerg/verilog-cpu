# Open-source toolchain for the CPU: Icarus Verilog (terminal board + tests), Verilator
# (lint + C++ model for the web board) and Emscripten (C++ -> WebAssembly).
# Synthesis for the real DE0 still needs Quartus II 13.1, see README.

# ---- sim: ./run.sh, ./run.sh test -----------------------------------------
FROM ubuntu:24.04 AS sim
RUN apt-get update -qq \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
      iverilog verilator python3 make g++ \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /cpu
COPY src src
COPY tooling/*.mif tooling/
COPY sim sim
COPY scripts scripts
RUN mkdir -p build \
 && iverilog -g2005 -s board_tb -o build/board.vvp sim/board_tb.v src/synthesis/modules/*.v
ENV PYTHONUNBUFFERED=1
ENTRYPOINT ["python3", "/cpu/sim/board.py"]

# ---- verilated: the same RTL as a C++ model (DIVISOR=2, as in simulation) --
FROM sim AS verilated
RUN verilator --cc -Wno-fatal -Wno-lint --public-flat-rw -GDIVISOR=2 --top-module top \
      src/synthesis/modules/*.v --Mdir build/obj \
 && cp -r /usr/share/verilator/include build/vinc
COPY web web
RUN python3 web/gen_programs.py tooling/mem_init.mif tooling/mem_init_test.mif > build/programs.js

# ---- web: compile to WebAssembly and assemble the static site in /site ------
FROM --platform=linux/amd64 emscripten/emsdk:3.1.64 AS web
WORKDIR /cpu
COPY --from=verilated /cpu/build build
COPY --from=verilated /cpu/web web
RUN mkdir -p /site \
 && em++ -O2 -std=c++17 -include cstdint -DVL_IGNORE_UNKNOWN_ARCH \
      -Ibuild/obj -Ibuild/vinc -Ibuild/vinc/vltstd \
      web/board.cpp build/obj/*.cpp build/vinc/verilated.cpp build/vinc/verilated_threads.cpp \
      -sMODULARIZE -sEXPORT_ES6 -sALLOW_MEMORY_GROWTH -sENVIRONMENT=web,node \
      -o /site/board.mjs \
 && cp web/index.html build/programs.js /site/
EXPOSE 8000
CMD ["python3", "-m", "http.server", "8000", "--directory", "/site"]
