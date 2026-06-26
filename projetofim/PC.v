`timescale 1ns / 1ps

// =============================================================================
//  PC — Program Counter
//
//  - 32-bit counter, word-addressed
//  - Updates on negedge clk (consistent with processor timing convention)
//  - Asynchronous reset (rst) forces PC = 0 immediately
//  - Starts at 0 on initialization
//  - Locked if next PC >= 2^10 (1024) — exceeds ROM bounds
//  - Locked if HLT is active
//
//  Priority (highest to lowest):
//    1. HLT or out-of-bounds  → PC frozen
//    2. JR                    → PC = JRAddr (register RD)
//    3. Jump (JMP/JAL)        → PC = JumpAddr (END26)
//    4. Branch (condition met)→ PC = PC + 1 + BranchOffset (END14 sign-extended)
//    5. Normal                → PC = PC + 1
//
//  Notes:
//    - JAL saves PC to RAL before jumping — that is handled by the register
//      bank (RALWrite signal from Control Unit), not by this module.
//    - BranchOffset is END14 already sign-extended to 32 bits (from outside).
//    - JumpAddr is END26 already sign-extended to 32 bits (from outside).
//    - Bounds check applies to ALL next PC sources (JR, Jump, Branch, Normal).
// =============================================================================

module PC (
    input  wire        clk,
    input  wire        rst,            // Asynchronous reset — PC = 0
    input  wire        HLT,            // Halt — freeze PC
    input  wire        Jump,           // JMP or JAL — PC = JumpAddr
    input  wire        JR,             // JR — PC = JRAddr
    input  wire        Branch,         // Branch condition is true
    input  wire [31:0] JumpAddr,       // END26 sign-extended (JMP, JAL)
    input  wire [31:0] BranchOffset,   // END14 sign-extended (BEQ, BNE, BLT, BGT)
    input  wire [31:0] JRAddr,         // RD register value (JR)
    output reg  [31:0] PC_out          // Current PC (connects to ROM addr)
);

    // ROM upper bound — matches MemInstrucao ADDR_WIDTH = 10
    localparam MAX_PC = 32'd1023;      // 2^10 - 1

    // ── Initialization ────────────────────────────────────────────────────────
    initial PC_out = 32'b0;

    // ── Next PC computation wire ──────────────────────────────────────────────
    reg [31:0] next_pc;

    always @(*) begin
        if      (JR)     next_pc = JRAddr;
        else if (Jump)   next_pc = JumpAddr;
        else if (Branch) next_pc = PC_out + 1 + BranchOffset;
        else             next_pc = PC_out + 1;
    end

    // ── Sequential update — negedge, async reset ──────────────────────────────
    always @(negedge clk or posedge rst) begin
        if (rst)
            PC_out <= 32'b0;           // async reset, independent of clock
        else if (HLT || next_pc > MAX_PC)
            PC_out <= PC_out;          // freeze
        else
            PC_out <= next_pc;
    end

endmodule