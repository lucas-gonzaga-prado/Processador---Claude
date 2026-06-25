`timescale 1ns / 1ps

// =============================================================================
//  MemDados — Data Memory (RAM)
//
//  - 1024 x 32-bit words (adjustable via ADDR_WIDTH)
//  - Synchronous write : commits on posedge write_clk (STORE, PUSH)
//  - Synchronous read  : data available on negedge read_clk (LOAD, POP)
//  - Two clock inputs  : write_clk and read_clk — connect both to the same
//                        processor clock to maintain monocycle behavior.
//
//  Timing (consistent with processor convention):
//    posedge write_clk : RAM write commits   (STORE, PUSH)
//    negedge read_clk  : RAM read available  (LOAD, POP)
// =============================================================================

module MemDados
#(
    parameter DATA_WIDTH = 32,   // Word size (32 bits)
    parameter ADDR_WIDTH = 10    // 2^10 = 1024 memory slots
)
(
    input  wire                    write_clk,   // Write clock (posedge = STORE/PUSH commits)
    input  wire                    read_clk,    // Read clock  (negedge = LOAD/POP available)
    input  wire                    MemWrite,    // Write enable (STORE, PUSH)
    input  wire [(ADDR_WIDTH-1):0] write_addr,  // Write address
    input  wire [(ADDR_WIDTH-1):0] read_addr,   // Read address
    input  wire [(DATA_WIDTH-1):0] data_in,     // Data to write
    output reg  [(DATA_WIDTH-1):0] data_out     // Data read
);

    // ── RAM array ─────────────────────────────────────────────────────────────
    reg [(DATA_WIDTH-1):0] ram [(2**ADDR_WIDTH)-1:0];

    // ── Initialization (zeroes all positions at simulation start) ─────────────
    integer i;
    initial begin
        for (i = 0; i < 2**ADDR_WIDTH; i = i + 1)
            ram[i] = 32'b0;
    end

    // ── Synchronous write — posedge ───────────────────────────────────────────
    // STORE and PUSH commit at the midpoint of the instruction cycle.
    always @(posedge write_clk) begin
        if (MemWrite)
            ram[write_addr] <= data_in;
    end

    // ── Synchronous read — negedge ────────────────────────────────────────────
    // LOAD and POP: data available at the end of the instruction cycle,
    // after the write has already committed at posedge.
    always @(negedge read_clk) begin
        data_out <= ram[read_addr];
    end

endmodule