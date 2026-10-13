// Virtual DE0 board for simulation: runs the unmodified `top` (CPU + memory + 7-segment
// display) and prints one trace line per CPU clock for sim/board.py to render.
//
// Plusargs:  +mem=<program.hex>   memory image (converted from a Quartus .mif)
//            +in=<inputs.hex>     values the "operator" sets on SW3..SW0, one per IN instruction
//            +maxcyc=<n>          safety limit on CPU clocks (default 2000)
`timescale 1ns/1ns
module board_tb;
    reg  clk = 0;
    reg  [9:0] sw = 10'b10_0000_0000;   // SW9 is reset (1 = run)
    wire [9:0] led;
    wire [27:0] hex;

    // DIVISOR=2: the CPU clock is CLOCK_50/4 instead of 1 Hz, same logic otherwise.
    top #(.DIVISOR(2), .FILE_NAME("unused.mif")) dut (
        .clk(clk), .rst_n(sw[9]), .btn(3'b000), .sw(sw[8:0]), .led(led), .hex(hex)
    );

    always #5 clk = ~clk;

    reg [15:0] inputs [0:63];
    reg [1023:0] file;
    integer n_inputs = 0, next_input = 0, cyc = 0, maxcyc = 2000, halted_for = 0;

    initial begin
        if (!$value$plusargs("mem=%s", file)) begin
            $display("usage: +mem=<program.hex> [+in=<inputs.hex>] [+maxcyc=N]");
            $finish;
        end
        $readmemh(file, dut.memory_inst.mem, 0, 63);
        if ($value$plusargs("in=%s", file)) begin
            $readmemh(file, inputs);
            while (n_inputs < 64 && inputs[n_inputs] !== 16'hxxxx) n_inputs = n_inputs + 1;
        end
        if ($value$plusargs("maxcyc=%d", maxcyc)) ;
        // Flip SW9 down and up again: reset is a falling edge on rst_n, exactly like on the board.
        #2  sw[9] = 1'b0;
        #21 sw[9] = 1'b1;
    end

    // The operator: while an IN instruction is being decoded, set the switches before the
    // CPU samples them (the store happens on the next rising edge).
    always @(negedge dut.clk_divided)
        if (sw[9] && dut.cpu_inst.state_reg == 5'd4 && dut.cpu_inst.ir_h_out[15:12] == 4'h7
            && next_input < n_inputs) begin
            sw[3:0] = inputs[next_input][3:0];
            next_input = next_input + 1;
        end

    // One line per CPU clock (after it settles):
    // T <cyc> <state> <pc> <sp> <ir_h> <ir_l> <led> <sw> <hex> <mem[1..7]> <mem_we> <mem_addr>
    always @(posedge dut.clk_divided) if (sw[9]) begin
        #1;
        cyc = cyc + 1;
        $display("T %0d %0d %0d %0d %h %h %h %h %h %h %h %h %h %h %h %h %0d %0d", cyc,
            dut.cpu_inst.state_reg, dut.pc_wire, dut.sp_wire,
            dut.cpu_inst.ir_h_out, dut.cpu_inst.ir_l_out, led[4:0], sw, hex,
            dut.memory_inst.mem[1], dut.memory_inst.mem[2], dut.memory_inst.mem[3],
            dut.memory_inst.mem[4], dut.memory_inst.mem[5], dut.memory_inst.mem[6],
            dut.memory_inst.mem[7], dut.mem_we_wire, dut.mem_addr_wire);
        if (dut.cpu_inst.state_reg == 5'd0) halted_for = halted_for + 1;
        if (halted_for == 3 || cyc >= maxcyc) $finish;
    end
endmodule
