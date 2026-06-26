`timescale 1ns / 1ps

// =============================================================================
//  MemDados — Data Memory (RAM)
//
//  - 1024 x 32-bit words (adjustable via ADDR_WIDTH)
//  - Synchronous write  : commits on posedge write_clk (STORE, PUSH)
//  - Asynchronous read  : data available combinationally (LOAD, POP)
//  - read_clk is kept in the port list for compatibility but is unused.
//
//  Timing (consistent with processor convention):
//    posedge write_clk : RAM write commits   (STORE, PUSH)
//    async read        : data_out tracks ram[read_addr] continuously, so the
//                        negedge register write captures the correct word.
// =============================================================================

module MemDados
#(
    parameter DATA_WIDTH = 32,   // Word size (32 bits)
    parameter ADDR_WIDTH = 10    // 2^10 = 1024 memory slots
)
(
    input  wire                    write_clk,   // Write clock (posedge = STORE/PUSH commits)
    input  wire                    read_clk,    // Read clock  (unused — read is async)
    input  wire                    MemWrite,    // Write enable (STORE, PUSH)
    input  wire [(ADDR_WIDTH-1):0] write_addr,  // Write address
    input  wire [(ADDR_WIDTH-1):0] read_addr,   // Read address
    input  wire [(DATA_WIDTH-1):0] data_in,     // Data to write
    output wire [(DATA_WIDTH-1):0] data_out     // Data read
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

    // ── Asynchronous read ─────────────────────────────────────────────────────
    // LOAD and POP: data available combinationally, like the instruction ROM.
    // Required so the register bank (which writes on negedge) captures the
    // freshly addressed word in the SAME cycle — a registered read would lag
    // by one cycle and write stale data.
    assign data_out = ram[read_addr];

endmodule