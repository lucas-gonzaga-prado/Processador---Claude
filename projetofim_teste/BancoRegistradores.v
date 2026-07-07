`timescale 1ns / 1ps

// =============================================================================
//  BancoRegistradores — 64 x 32-bit register file
//
//  Special registers (fixed addresses):
//    R0  — RZ  : constant zero (writes ignored, reads always 0)
//    R61 — RH  : MUL high word / DIV remainder
//    R62 — RAL : return-address link (saved by JAL)
//    R63 — RPI : stack pointer (top of stack in data memory)
//
//  Read ports  : combinational (asynchronous).
//  Write ports : synchronous on negedge clk; asynchronous reset (active high).
//    Four write paths (last wins on the same address): normal RegWrite (RD),
//    plus dedicated RHWrite (R61), RALWrite (R62) and RPIWrite (R63).
// =============================================================================

module BancoRegistradores (
    input  wire        clk,
    input  wire        rst,                 // asynchronous reset (active high)

    // ── Read ports ────────────────────────────────────────────────────────────
    input  wire [5:0]  ReadReg1,            // register number for port 1
    input  wire [5:0]  ReadReg2,            // register number for port 2
    output wire [31:0] ReadData1,           // data read from ReadReg1
    output wire [31:0] ReadData2,           // data read from ReadReg2

    // ── Normal write port ──────────────────────────────────────────────────────
    input  wire        RegWrite,            // write enable
    input  wire [5:0]  WriteReg,            // destination register (RD field)
    input  wire [31:0] WriteData,           // data to write (from ALU or memory)

    // ── Dedicated write: RH (R61) — MUL high / DIV remainder ───────────────────
    input  wire        RHWrite,
    input  wire [31:0] RH,

    // ── Dedicated write: RPI (R63) — stack pointer ─────────────────────────────
    input  wire        RPIWrite,
    input  wire [31:0] RPI,

    // ── Dedicated write: RAL (R62) — return-address link ───────────────────────
    input  wire        RALWrite,
    input  wire [31:0] RAL
);

    reg [31:0] regs [0:63];

    // ── Combinational read (RZ / R0 always reads as 0) ─────────────────────────
    assign ReadData1 = (ReadReg1 == 6'd0) ? 32'b0 : regs[ReadReg1];
    assign ReadData2 = (ReadReg2 == 6'd0) ? 32'b0 : regs[ReadReg2];

    // ── Synchronous write / asynchronous reset ─────────────────────────────────
    integer i;
    always @(negedge clk or posedge rst) begin
        if (rst) begin
            // Async reset fires immediately on KEY[0], independent of the clock.
            for (i = 0; i < 64; i = i + 1)
                regs[i] <= 32'b0;
        end else begin
            // 1. Normal write (blocked for RZ / R0).
            if (RegWrite && (WriteReg != 6'd0))
                regs[WriteReg] <= WriteData;

            // 2..4. Dedicated writes override a simultaneous RegWrite to R61/R62/R63.
            if (RHWrite)  regs[6'd61] <= RH;
            if (RALWrite) regs[6'd62] <= RAL;
            if (RPIWrite) regs[6'd63] <= RPI;
        end
    end

endmodule
