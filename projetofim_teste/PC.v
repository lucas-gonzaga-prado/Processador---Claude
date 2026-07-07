`timescale 1ns / 1ps

// =============================================================================
//  PC — Program Counter
//
//  - 32-bit counter, word-addressed (drives the instruction ROM address).
//  - Updates on negedge clk (same edge as the register bank and data RAM).
//  - Asynchronous reset (rst) forces PC = 0 immediately.
//  - Frozen while en = 0 (waiting for the first KEY press), on HLT, or when the
//    next PC would exceed the ROM bounds.
//
//  Next-PC priority (highest to lowest):
//    1. !en / HLT / out-of-bounds  → PC frozen
//    2. JR                         → PC = JRAddr        (register RD)
//    3. Jump (JMP/JAL)             → PC = JumpAddr      (END26)
//    4. Branch (condition met)     → PC = PC + 1 + BranchOffset (END14)
//    5. Normal                     → PC = PC + 1
//
//  Notes:
//    - JAL saves the return address to RAL in the register bank, not here.
//    - BranchOffset and JumpAddr arrive already sign-extended to 32 bits.
// =============================================================================

module PC (
    input  wire        clk,
    input  wire        rst,            // asynchronous reset — PC = 0
    input  wire        en,             // clock-enable — 0 freezes the PC (idle state)
    input  wire        HLT,            // halt — freeze PC
    input  wire        Jump,           // JMP or JAL — PC = JumpAddr
    input  wire        JR,             // JR — PC = JRAddr
    input  wire        Branch,         // branch condition is true
    input  wire [31:0] JumpAddr,       // END26 sign-extended (JMP, JAL)
    input  wire [31:0] BranchOffset,   // END14 sign-extended (BEQ, BNE, BLT, BGT)
    input  wire [31:0] JRAddr,         // RD register value (JR)
    output reg  [31:0] PC_out          // current PC (connects to ROM addr)
);

    // ROM upper bound — matches MemInstrucao ADDR_WIDTH = 7.
    localparam MAX_PC = 32'd127;       // 2^7 - 1 (ROM = 128 instructions)

    initial PC_out = 32'b0;

    // Combinational next-PC.
    reg [31:0] next_pc;
    always @(*) begin
        if      (JR)     next_pc = JRAddr;
        else if (Jump)   next_pc = JumpAddr;
        else if (Branch) next_pc = PC_out + 1 + BranchOffset;
        else             next_pc = PC_out + 1;
    end

    // Sequential update — negedge, asynchronous reset.
    always @(negedge clk or posedge rst) begin
        if (rst)
            PC_out <= 32'b0;                              // async reset: PC = 0
        else if (!en || HLT || next_pc > MAX_PC)
            PC_out <= PC_out;                            // frozen: idle / HLT / end of ROM
        else
            PC_out <= next_pc;
    end

endmodule
