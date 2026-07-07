`timescale 1ns / 1ps

// =============================================================================
//  Extensor — Immediate field extractor + sign extension
//
//  Extracts one of the three immediate fields from the instruction and
//  sign-extends it to 32 bits, chosen by imm_sel (from the Control Unit).
//
//  Instruction formats:
//    Type I : OP(6) | RD(6) | RS(6) | END14(14) — bits [13:0]
//    Type I*: OP(6) | RD(6) | END20(20)         — bits [19:0]
//    Type J : OP(6) | END26(26)                 — bits [25:0]
// =============================================================================

module Extensor (
    input  wire [31:0] instruction,  // full 32-bit instruction
    input  wire [1:0]  imm_sel,      // which immediate field to extract
    output wire [31:0] immediate     // sign-extended immediate (32 bits)
);

    // imm_sel: 00 = END14, 01 = END20, 10 = END26, 11 = reserved (0)
    wire [31:0] end14_extended;
    wire [31:0] end20_extended;
    wire [31:0] end26_extended;

    // Sign-extend each field by replicating its MSB up to bit 31.
    assign end14_extended = {{18{instruction[13]}}, instruction[13:0]};
    assign end20_extended = {{12{instruction[19]}}, instruction[19:0]};
    assign end26_extended = {{6{instruction[25]}}, instruction[25:0]};

    assign immediate = (imm_sel == 2'b00) ? end14_extended :
                       (imm_sel == 2'b01) ? end20_extended :
                       (imm_sel == 2'b10) ? end26_extended :
                       32'b0;

endmodule
