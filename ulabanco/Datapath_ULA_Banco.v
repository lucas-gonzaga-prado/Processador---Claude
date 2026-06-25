`timescale 1ns / 1ps
 
// =============================================================================
//  Datapath_ULA_Banco — Integration of ULA + Register Bank
//
//  Dataflow:
//    Registrador1 → BancoReg → Dado1 ──────────────────────► A (ULA)
//    Registrador2 → BancoReg → Dado2 ──► MUX (ULASource) ──► B (ULA)
//                              Imediato ─┘
//
//    ULA → Result      ──► MUX (MemToReg) ──► DadoParaEscrita (BancoReg)
//          DadoMemoria ─┘
//    ULA → Result_High ──────────────────────► RH (BancoReg)
//
//  Control signals (driven by the Control Unit in the future):
//    ULASource : 0 = Dado2 (RT),  1 = Imediato
//    MemToReg  : 0 = ULA Result,  1 = Data Memory (future)
// =============================================================================
  
module Datapath_ULA_Banco (
    input  wire        clk,
	 //input  wire        rst,      Tinha sido recomendado colocar isso, mas não útil agora
 
    // ── Register addresses (from instruction decode) ─────────────────────────
    input  wire [5:0]  Registrador1,      // RS
    input  wire [5:0]  Registrador2,      // RT
    input  wire [5:0]  RegistradorEscrita,// RD
 
    // ── Immediate value (sign-extended, from instruction decode) ─────────────
    input  wire [31:0] Imediato,          // IM14 / IM20 already extended to 32b
 
    // ── Data memory output (for LOAD instructions — future) ──────────────────
    input  wire [31:0] DadoMemoria,       // Output of data memory
 
    // ── Dedicated write data ─────────────────────────────────────────────────
    input  wire [31:0] RPI,               // Updated stack pointer
    input  wire [31:0] RAL,               // Return address (from JAL)
 
    // ── Control signals ───────────────────────────────────────────────────────
    input  wire        RegWrite,          // Enable normal register write
    input  wire        RHWrite,           // Enable RH write
    input  wire        RPIWrite,          // Enable RPI write
    input  wire        RALWrite,          // Enable RAL write
    input  wire [3:0]  ALUControl,        // ALU operation selector
    input  wire        ULASource,         // 0 = RT,  1 = Immediate
    input  wire        MemToReg,          // 0 = ALU Result, 1 = Data Memory
 
    // ── Outputs ───────────────────────────────────────────────────────────────
    output wire        Zero,              // ALU Zero flag (BEQ, BNE)
    output wire        Negativo,          // ALU Negative flag (BLT, BGT)
    output wire [31:0] ResultadoULA       // ALU result (address for MEM, etc.)
);
 
    // ── Internal wires ────────────────────────────────────────────────────────
    wire [31:0] Dado1, Dado2;
    wire [31:0] EntradaB;           // MUX output → ULA operand B
    wire [31:0] ResultULA;          // ULA main result
    wire [31:0] ResultULA_High;     // ULA high result (MUL/DIV)
    wire [31:0] DadoParaEscrita;    // MUX output → register write data
 
    // ── MUX 1: ULA operand B — RT register vs Immediate ──────────────────────
    assign EntradaB = (ULASource == 1'b0) ? Dado2 : Imediato;
 
    // ── MUX 2: Register write data — ALU result vs Data memory ───────────────
    assign DadoParaEscrita = (MemToReg == 1'b0) ? ResultULA : DadoMemoria;
 
    // ── Result exposed to outside (for memory address, branches, etc.) ────────
    assign ResultadoULA = ResultULA;
 
    // ── ULA instantiation ─────────────────────────────────────────────────────
    ULA ula (
        .A           (Dado1),
        .B           (EntradaB),
        .ALUControl  (ALUControl),
        .Result      (ResultULA),
        .Result_High (ResultULA_High),
        .Zero        (Zero),
        .Negativo    (Negativo)
    );
 
    // ── Register bank instantiation ───────────────────────────────────────────
    BancoRegistradores banco (
        .clk               (clk),
		  //.rst               (rst),      foi recomendado colocar isso agora, mas não foi útil
        .Registrador1      (Registrador1),
        .Registrador2      (Registrador2),
        .Dado1             (Dado1),
        .Dado2             (Dado2),
        .RegWrite          (RegWrite),
        .RegistradorEscrita(RegistradorEscrita),
        .DadoParaEscrita   (DadoParaEscrita),
        .RHWrite           (RHWrite),
        .RH                (ResultULA_High),
        .RPIWrite          (RPIWrite),
        .RPI               (RPI),
        .RALWrite          (RALWrite),
        .RAL               (RAL)
    );
 
endmodule