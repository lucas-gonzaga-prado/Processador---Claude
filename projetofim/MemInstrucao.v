`timescale 1ns / 1ps

// =============================================================================
//  MemInstrucao — Instruction Memory (ROM)
//
//  - 128 x 32-bit words (adjustable via ADDR_WIDTH)
//  - Asynchronous read: instruction available immediately when PC changes
//  - Initialized from external file via $readmemb
//  - No write port: ROM is read-only during execution
//
//  Instruction format: 32 bits (matches processor ISA)
//  Address: word-addressed (PC connects directly to addr)
//
//  ISA opcodes loaded (37 instructions):
//    ADD, ADDI, SUB, SUBI, MUL, MULI, DIV, DIVI,
//    AND, ANDI, OR, ORI, NOR, XNOR, SL, SR,
//    MOV, MOVI, LOADR, LOADD, LOADI, STORER, STORED, STOREI,
//    PUSH, POP, BEQ, BNE, BLT, BGT, JMP, JAL,
//    JR, IN, OUT, NOP, HLT
// =============================================================================

module MemInstrucao
#(
    parameter DATA_WIDTH = 32,   // Instruction width (32 bits)
    parameter ADDR_WIDTH = 7     // 2^7 = 128 instruction slots
)
(
    input  wire [(ADDR_WIDTH-1):0] addr,   // PC (word-addressed)
    output wire [(DATA_WIDTH-1):0] q       // Instruction output
);

    // ── ROM array ─────────────────────────────────────────────────────────────
    reg [(DATA_WIDTH-1):0] rom [(2**ADDR_WIDTH)-1:0];

    // ── Initialization from file ──────────────────────────────────────────────
    // File format: one 32-bit binary instruction per line
    // Example line: 00000100001000100000000000001010  (ADD R1, R2, R10)
    initial
    begin
        $readmemb("instrucoes.txt", rom);
    end

    // ── Asynchronous read ─────────────────────────────────────────────────────
    // No clock needed: instruction is available immediately when addr changes.
    // This is required for single-cycle execution.
    assign q = rom[addr];

endmodule