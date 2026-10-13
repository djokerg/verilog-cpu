// WebAssembly wrapper around the Verilator model of `top` (CPU + memory + 7-segment display).
// JavaScript drives the board inputs (SW9 reset, SW3..SW0) and the 50 MHz clock and reads
// back exactly what the board shows; nothing about the CPU is reimplemented here.
#include <cstdint>
#include "Vtop.h"
#include "Vtop___024root.h"
#include "verilated.h"
#include <emscripten/emscripten.h>

static VerilatedContext* ctx;
static Vtop* top;
#define R top->rootp

extern "C" {
EMSCRIPTEN_KEEPALIVE void board_init() {
    ctx = new VerilatedContext;
    top = new Vtop{ctx};
    top->clk = 0;
    top->rst_n = 1;
    top->btn = 0;
    top->sw = 0;
    top->eval();
}
EMSCRIPTEN_KEEPALIVE void mem_write(int addr, int value) { R->top__DOT__memory_inst__DOT__mem[addr & 63] = value; }
EMSCRIPTEN_KEEPALIVE int mem_read(int addr) { return R->top__DOT__memory_inst__DOT__mem[addr & 63]; }

// SW9 drives rst_n (reset is its falling edge), SW8..SW0 go to top.sw.
EMSCRIPTEN_KEEPALIVE void set_switches(int sw) {
    top->rst_n = (sw >> 9) & 1;
    top->sw = sw & 0x1FF;
    top->eval();
}

// Run the 50 MHz clock until the divided CPU clock has a rising edge: one CPU clock.
EMSCRIPTEN_KEEPALIVE void cpu_clock() {
    for (int i = 0; i < 16; i++) {
        uint8_t before = R->top__DOT__clk_divided;
        top->clk = 1; top->eval();
        top->clk = 0; top->eval();
        if (!before && R->top__DOT__clk_divided) return;
    }
}

EMSCRIPTEN_KEEPALIVE int led() { return top->led; }
EMSCRIPTEN_KEEPALIVE int hex() { return top->hex; }
EMSCRIPTEN_KEEPALIVE int state() { return R->top__DOT__cpu_inst__DOT__state_reg; }
EMSCRIPTEN_KEEPALIVE int pc() { return R->top__DOT__pc_wire; }
EMSCRIPTEN_KEEPALIVE int sp() { return R->top__DOT__sp_wire; }
EMSCRIPTEN_KEEPALIVE int ir_h() { return R->top__DOT__cpu_inst__DOT__ir_h_out; }
EMSCRIPTEN_KEEPALIVE int ir_l() { return R->top__DOT__cpu_inst__DOT__ir_l_out; }
EMSCRIPTEN_KEEPALIVE int acc() { return R->top__DOT__cpu_inst__DOT__acc_out; }
EMSCRIPTEN_KEEPALIVE int mem_addr() { return R->top__DOT__mem_addr_wire; }
EMSCRIPTEN_KEEPALIVE int mem_we() { return R->top__DOT__mem_we_wire; }
}
