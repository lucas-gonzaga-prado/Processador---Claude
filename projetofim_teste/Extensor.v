`timescale 1ns / 1ps

// =============================================================================
//  ImmExtend — Immediate Field Extractor
//
//  Extracts and sign-extends immediate fields from the instruction based on
//  the instruction type (determined by imm_sel from the Control Unit).
//
//  Instruction formats:
//    Type I : OP(6) | RD(6) | RS(6) | IMM14(14) — bits [13:0]
//    Type I*: OP(6) | RD(6) | END20(20)         — bits [19:0]
//    Type J : OP(6) | END26(26)                 — bits [25:0]
//
//  Sign extension: MSB of field is replicated to all higher bits to 32 bits.
// =============================================================================

module Extensor (
    input  wire [31:0] instruction,  // Full 32-bit instruction
    input  wire [1:0]  imm_sel,      // Select which immediate field to extract
    output wire [31:0] imediato      // Sign-extended immediate to 32 bits
);

    // imm_sel encoding:
    //   00 = END14 (14-bit immediate, Type I)
    //   01 = END20 (20-bit immediate, Type I*)
    //   10 = END26 (26-bit immediate, Type J)
    //   11 = reserved (output 0)

    wire [31:0] end14_extended;
    wire [31:0] end20_extended;
    wire [31:0] end26_extended;

    // ── Extract END14 (bits [13:0]) and sign-extend to 32 bits ────────────────
    // MSB at bit 13; replicate to bits [31:14]
    assign end14_extended = {{18{instruction[13]}}, instruction[13:0]};

    // ── Extract END20 (bits [19:0]) and sign-extend to 32 bits ────────────────
    // MSB at bit 19; replicate to bits [31:20]
    assign end20_extended = {{12{instruction[19]}}, instruction[19:0]};

    // ── Extract END26 (bits [25:0]) and sign-extend to 32 bits ────────────────
    // MSB at bit 25; replicate to bits [31:26]
    assign end26_extended = {{6{instruction[25]}}, instruction[25:0]};

    // ── Mux: select which immediate to output ────────────────────────────────
    assign imediato = (imm_sel == 2'b00) ? end14_extended :
                      (imm_sel == 2'b01) ? end20_extended :
                      (imm_sel == 2'b10) ? end26_extended :
                      32'b0;

endmodule