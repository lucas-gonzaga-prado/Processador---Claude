`timescale 1ns / 1ps

// =============================================================================
//  MemDados — Data Memory (RAM)
//
//  - 1024 x 32-bit words (adjustable via ADDR_WIDTH)
//  - Synchronous write  : commits on negedge write_clk (STORE, PUSH)
//  - Asynchronous read  : data available combinationally (LOAD, POP)
//  - read_clk is kept in the port list for compatibility but is unused.
//
//  Timing (consistent with processor convention):
//    negedge write_clk : RAM write commits, on the SAME edge as the PC and
//                        register-bank updates — so all state of one
//                        instruction commits atomically with the current
//                        (not the next) instruction's control signals.
//    async read        : data_out tracks ram[read_addr] continuously, so the
//                        negedge register write captures the correct word.
// =============================================================================

module MemDados
#(
    parameter DATA_WIDTH = 32,   // Word size (32 bits)
    parameter ADDR_WIDTH = 8    // 2^8 = 256 memory slots
)
(
    input  wire                    write_clk,   // Write clock (negedge = STORE/PUSH commits)
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

    // ── Synchronous write — negedge ───────────────────────────────────────────
    // STORE and PUSH commit on the same negedge as the PC and register bank,
    // using the CURRENT instruction's signals. Writing on posedge (the other
    // half of the step-button pulse) would commit after the PC already advanced
    // to the next instruction, losing/corrupting the store.
    always @(negedge write_clk) begin
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