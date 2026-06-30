`timescale 1ns / 1ps

// =============================================================================
//  Processador — Top-level integration
//
//  Modules instantiated:
//    pc              — Program Counter
//    MemInstrucao    — Instruction Memory (ROM, async read)
//    ucontrole       — Control Unit
//    ImmExtend       — Immediate field extractor + sign extension
//    ULA             — Arithmetic Logic Unit
//    BancoRegistradores — Register Bank (64 x 32-bit)
//    MemDados        — Data Memory (RAM)
//
//  Instruction field decode (32-bit instruction):
//    [31:26] = opcode
//    [25:20] = RD field
//    [19:14] = RS field
//    [13:8]  = RT field
//    [13:0]  = END14  (Type I)
//    [19:0]  = END20  (Type I*)
//    [25:0]  = END26  (Type J)
//
//  Register address muxing rules:
//    Registrador1:
//      JR            → RD field  (jump target register)
//      PUSH / POP    → R63       (RPI — stack pointer)
//      MOV/MOVI/LOADI/STOREI → R0 (RZ — approach B: A=0, Result=0+B=B)
//      default       → RS field
//
//    Registrador2:
//      STORE / PUSH  → RD field  (data to write to memory)
//      MOV           → RS field  (source register, B=RS, A=RZ)
//      default       → RT field
//
//  Memory address routing:
//    write_addr: PUSH → RPI+1 | STORER → Dado1(RS) | others → ResultULA
//    read_addr : POP  → Dado1(RPI) | LOADR → Dado1(RS) | others → ResultULA
// =============================================================================

module Processador (
    input  wire        clk,
    input  wire        en,    // clock-enable: 1 habilita um passo, 0 congela o estado
    input  wire        rst,

    input  wire [31:0] Switches,
    output wire [31:0] Display,

    // =============================
    // DEBUG - sinais para waveform
    // =============================
    output wire [31:0] dbg_PC,
    output wire [31:0] dbg_instruction,
    output wire [5:0]  dbg_opcode,

    output wire [31:0] dbg_Dado1,
    output wire [31:0] dbg_Dado2,
    output wire [31:0] dbg_imediato,

    output wire [31:0] dbg_ResultULA,
    output wire [31:0] dbg_DadoMemoria,

    output wire        dbg_Zero,
    output wire        dbg_Negativo,

    output wire        dbg_RegWrite,
    output wire        dbg_MemRead,
    output wire        dbg_MemWrite,

    output wire        dbg_HLT,
    output wire        dbg_BranchTaken
);

    // =========================================================================
    //  Instruction fields
    // =========================================================================
    wire [31:0] instruction;
    wire [5:0]  opcode   = instruction[31:26];
    wire [5:0]  RD_field = instruction[25:20];
    wire [5:0]  RS_field = instruction[19:14];
    wire [5:0]  RT_field = instruction[13:8];

    // ── Opcode constants (for address muxing in this module) ──────────────────
    localparam MOV_OP    = 6'b010000;
    localparam MOVI_OP   = 6'b010001;
    localparam LOADR_OP  = 6'b010010;
    localparam LOADI_OP  = 6'b010100;
    localparam STORER_OP = 6'b010101;
    localparam STOREI_OP = 6'b010111;

    // =========================================================================
    //  Control signals
    // =========================================================================
    wire        RegWrite, RHWrite, RPIWrite, RALWrite;
    wire        ULASource;
    wire [3:0]  ULAControl;
    wire        MemRead, MemWrite, MemToReg;
    wire        Branch;
    wire [1:0]  BranchCond;
    wire        Jump, JR, HLT;
    wire        Push, Pop, Pilha;
    wire        SwitchesOn, PortaON;
    wire [1:0]  imm_sel;

    // =========================================================================
    //  Internal wires
    // =========================================================================
    wire [31:0] PC_out;
    wire [31:0] imediato;
    wire [31:0] Dado1, Dado2;
    wire [31:0] ResultULA, ResultULA_High;
    wire [31:0] DadoParaEscrita;
    wire [31:0] DadoMemoria;
    wire        Zero, Negativo;

    // =========================================================================
    //  Register address muxing
    // =========================================================================

    // Registrador1 (→ Dado1 → ULA operand A)
    wire [5:0] Registrador1 =
        JR                  ? RD_field :   // JR: target is RD field
        (Push | Pop)        ? 6'd63    :   // PUSH/POP: read RPI (R63)
        (opcode == MOV_OP    ||
         opcode == MOVI_OP   ||
         opcode == LOADI_OP  ||
         opcode == STOREI_OP) ? 6'd0   :   // I* / MOV: A=RZ=0 (Approach B)
        RS_field;                           // default: RS

    // Registrador2 (→ Dado2 → ULA operand B or store data)
    wire [5:0] Registrador2 =
        (MemWrite | Push)   ? RD_field :   // STORE/PUSH: read RD (data to write)
        (opcode == MOV_OP)  ? RS_field :   // MOV: B=RS (A=RZ, result=RS)
        Branch              ? RD_field :   // Branch (Type I has no RT field —
                                            // comparison is RS vs RD, per ISA encoding)
        RT_field;                           // default: RT

    // =========================================================================
    //  Branch condition evaluation
    // =========================================================================
    wire BranchTaken = Branch && (
        (BranchCond == 2'b00) ?  Zero               :   // BEQ: Zero=1
        (BranchCond == 2'b01) ? ~Zero               :   // BNE: Zero=0
        (BranchCond == 2'b10) ?  Negativo           :   // BLT: Neg=1
                                 (~Negativo & ~Zero)     // BGT: Neg=0 & Zero=0
    );

    // =========================================================================
    //  ULA operand B mux
    // =========================================================================
    wire [31:0] EntradaB = ULASource ? imediato : Dado2;

    // =========================================================================
    //  Register write data mux
    //    Priority: SwitchesOn (IN) > MemToReg (LOAD) > ResultULA (ALU)
    // =========================================================================
    assign DadoParaEscrita = SwitchesOn ? Switches    :
                             MemToReg   ? DadoMemoria :
                             ResultULA;

    // =========================================================================
    //  Stack pointer (RPI) update for PUSH / POP
    //    Dado1 = current RPI (since Registrador1 = R63 for Push/Pop)
    // =========================================================================
    wire [31:0] RPI_val = Dado1;
    wire [31:0] RPI_new = Push ? RPI_val + 32'd1 : RPI_val - 32'd1;

    // =========================================================================
    //  Data memory address routing
    // =========================================================================

    // Write address:
    //   PUSH   → RPI+1 (pre-increment)
    //   STORER → RS directly (bypass ULA — see note in header)
    //   STORED / STOREI → ResultULA (RS+END14 or END20)
    wire [5:0] mem_write_addr =
        Push                    ? RPI_new[5:0] :
        (opcode == STORER_OP)   ? Dado1[5:0]   :
        ResultULA[5:0];

    // Read address:
    //   POP    → current RPI (Dado1 = R63)
    //   LOADR  → RS directly (bypass ULA)
    //   LOADD / LOADI → ResultULA (RS+END14 or END20)
    wire [5:0] mem_read_addr =
        Pop                     ? RPI_val[5:0] :
        (opcode == LOADR_OP)    ? Dado1[5:0]   :
        ResultULA[5:0];

    // Write data: always Dado2
    //   STORE: Dado2 = RD value (muxed above)
    //   PUSH:  Dado2 = RD value (muxed above)
    wire [31:0] mem_data_in = Dado2;

    // =========================================================================
    //  RAL: save return address (next instruction) before JAL jump
    //    Must be PC+1 — saving PC_out would return to the JAL itself (loop).
    // =========================================================================
    wire [31:0] RAL_in = PC_out + 32'd1;

    // =========================================================================
    //  Display output (OUT instruction)
    // =========================================================================
    assign Display = PortaON ? Dado1 : 32'b0;

    // =========================================================================
    //  Module instantiations
    // =========================================================================

    // ── Program Counter ───────────────────────────────────────────────────────
    PC pc (
        .clk          (clk),
        .rst          (rst),
        .en           (en),
        .HLT          (HLT),
        .Jump         (Jump),
        .JR           (JR),
        .Branch       (BranchTaken),
        .JumpAddr     (imediato),        // END26 sign-extended
        .BranchOffset (imediato),        // END14 sign-extended
        .JRAddr       (Dado1),           // RD register (Registrador1=RD for JR)
        .PC_out       (PC_out)
    );

    // ── Instruction Memory (ROM) ──────────────────────────────────────────────
    MemInstrucao rom (
        .addr (PC_out[6:0]),
        .q    (instruction)
    );

    // ── Control Unit ─────────────────────────────────────────────────────────
    ucontrole uc (
        .Opcode     (opcode),
        .RegWrite   (RegWrite),
        .RHWrite    (RHWrite),
        .RPIWrite   (RPIWrite),
        .RALWrite   (RALWrite),
        .ULASource  (ULASource),
        .ULAControl (ULAControl),
        .MemRead    (MemRead),
        .MemWrite   (MemWrite),
        .MemToReg   (MemToReg),
        .Branch     (Branch),
        .BranchCond (BranchCond),
        .Jump       (Jump),
        .JR         (JR),
        .HLT        (HLT),
        .Push       (Push),
        .Pop        (Pop),
        .Pilha      (Pilha),
        .SwitchesOn (SwitchesOn),
        .PortaON    (PortaON),
        .imm_sel    (imm_sel)
    );

    // ── Immediate Extractor ───────────────────────────────────────────────────
    Extensor ext (
        .instruction (instruction),
        .imm_sel     (imm_sel),
        .imediato    (imediato)
    );

    // ── ALU ───────────────────────────────────────────────────────────────────
    ULA ula (
        .A           (Dado1),
        .B           (EntradaB),
        .ALUControl  (ULAControl),
        .Result      (ResultULA),
        .Result_High (ResultULA_High),
        .Zero        (Zero),
        .Negativo    (Negativo)
    );

    // ── Register Bank ─────────────────────────────────────────────────────────
    BancoRegistradores banco (
        .clk                (clk),
        .rst                (rst),
        .Registrador1       (Registrador1),
        .Registrador2       (Registrador2),
        .Dado1              (Dado1),
        .Dado2              (Dado2),
        .RegWrite           (RegWrite & en),
        .RegistradorEscrita (RD_field),
        .DadoParaEscrita    (DadoParaEscrita),
        .RHWrite            (RHWrite  & en),
        .RH                 (ResultULA_High),
        .RPIWrite           (RPIWrite & en),
        .RPI                (RPI_new),
        .RALWrite           (RALWrite & en),
        .RAL                (RAL_in)
    );

    // ── Data Memory (RAM) ─────────────────────────────────────────────────────
    MemDados ram (
        .write_clk  (clk),
        .read_clk   (clk),
        .MemWrite   (MemWrite & en),
        .write_addr (mem_write_addr),
        .read_addr  (mem_read_addr),
        .data_in    (mem_data_in),
        .data_out   (DadoMemoria)
    );
	 
	     // =============================
    // DEBUG - conexões para waveform
    // =============================

    assign dbg_PC          = PC_out;
    assign dbg_instruction = instruction;
    assign dbg_opcode      = opcode;

    assign dbg_Dado1       = Dado1;
    assign dbg_Dado2       = Dado2;
    assign dbg_imediato    = imediato;

    assign dbg_ResultULA   = ResultULA;
    assign dbg_DadoMemoria = DadoMemoria;

    assign dbg_Zero        = Zero;
    assign dbg_Negativo    = Negativo;

    assign dbg_RegWrite    = RegWrite;
    assign dbg_MemRead     = MemRead;
    assign dbg_MemWrite    = MemWrite;

    assign dbg_HLT         = HLT;
    assign dbg_BranchTaken = BranchTaken;

endmodule