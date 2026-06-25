`timescale 1ns / 1ps

// =============================================================================
//  BancoRegistradores — 64 x 32-bit register file
//
//  Special register map (fixed addresses):
//    R0  (6'd0)  — RZ  : constant zero (writes ignored, reads always 0)
//    R60 (6'd60) — RL  : MUL low word / DIV quotient
//    R61 (6'd61) — RH  : MUL high word / DIV remainder
//    R62 (6'd62) — RAL : return address link (saved by JAL)
//    R63 (6'd63) — RPI : stack pointer (top of stack in data memory)
//
//  Read ports  : combinational (asynchronous)
//  Write ports : synchronous (rising edge)
// =============================================================================

module BancoRegistradores (
    input  wire        clk,
    input  wire        rst,                  // Synchronous reset, active high

    // ── Read ports ──────────────────────────────────────────────────────────
    input  wire [5:0]  Registrador1,         // RS address
    input  wire [5:0]  Registrador2,         // RT address

    output wire [31:0] Dado1,                // RS data out
    output wire [31:0] Dado2,                // RT data out

    // ── Normal write port ────────────────────────────────────────────────────
    input  wire        RegWrite,             // Write enable
    input  wire [5:0]  RegistradorEscrita,   // Destination address (RD field)
    input  wire [31:0] DadoParaEscrita,      // Write data (from ALU or memory)

    // ── Dedicated write: RH (R61) — MUL high / DIV remainder ────────────────
    input  wire        RHWrite,
    input  wire [31:0] RH,                   // Result_High from ALU

    // ── Dedicated write: RPI (R63) — stack pointer ───────────────────────────
    input  wire        RPIWrite,
    input  wire [31:0] RPI,                  // Updated stack pointer

    // ── Dedicated write: RAL (R62) — return address link ────────────────────
    input  wire        RALWrite,
    input  wire [31:0] RAL                   // Return address (saved by JAL)
);

    // ── Register array ───────────────────────────────────────────────────────
    reg [31:0] regs [0:63];

    // ── Combinational read ───────────────────────────────────────────────────
    // RZ (R0) always reads as zero; all others return their stored value.
    assign Dado1 = (Registrador1 == 6'd0) ? 32'b0 : regs[Registrador1];
    assign Dado2 = (Registrador2 == 6'd0) ? 32'b0 : regs[Registrador2];

    // ── Synchronous write ────────────────────────────────────────────────────
    integer i;

    always @(negedge clk) begin
        if (rst) begin
            // Reset all registers to zero.
            // RPI initial value is set by software; the register file has
            // no knowledge of the stack layout in data memory.
            for (i = 0; i < 64; i = i + 1)
                regs[i] <= 32'b0;
        end else begin

            // 1. Normal write (RegWrite) — blocked for RZ (R0)
            if (RegWrite && (RegistradorEscrita != 6'd0))
                regs[RegistradorEscrita] <= DadoParaEscrita;

            // 2. RH (R61) — overwrites any simultaneous RegWrite to R61
            if (RHWrite)
                regs[6'd61] <= RH;

            // 3. RAL (R62) — overwrites any simultaneous RegWrite to R62
            if (RALWrite)
                regs[6'd62] <= RAL;

            // 4. RPI (R63) — overwrites any simultaneous RegWrite to R63
            if (RPIWrite)
                regs[6'd63] <= RPI;

        end
    end
endmodule