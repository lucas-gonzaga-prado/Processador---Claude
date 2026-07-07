`timescale 1ns / 1ps

// =============================================================================
//  Processador — Processor core (datapath + control integration)
//
//  Instantiated by the top-level `projetofinal`. Wires together the PC, the
//  instruction ROM, the control unit, the immediate extractor, the ALU, the
//  register bank and the data RAM, plus the register/address muxing.
//
//  Instantiated modules:
//    PC                 — Program Counter
//    MemInstrucao       — Instruction Memory (ROM, async read)
//    ucontrole          — Control Unit
//    Extensor           — Immediate field extractor + sign extension
//    ULA                — Arithmetic Logic Unit
//    BancoRegistradores — Register Bank (64 x 32-bit)
//    MemDados           — Data Memory (RAM)
//
//  Instruction fields (32-bit):
//    [31:26]=opcode  [25:20]=RD  [19:14]=RS  [13:8]=RT
//    [13:0]=END14 (Type I)  [19:0]=END20 (Type I*)  [25:0]=END26 (Type J)
//
//  Register-address muxing:
//    ReadReg1 (-> ReadData1 -> ALU operand A):
//      JR                     -> RD field (jump target register)
//      PUSH / POP             -> R63      (RPI, stack pointer)
//      MOV/MOVI/LOADI/STOREI  -> R0       (RZ, so A=0 and result = 0 + B = B)
//      default                -> RS field
//    ReadReg2 (-> ReadData2 -> ALU operand B or store data):
//      STORE / PUSH           -> RD field (data to write to memory)
//      MOV                    -> RS field (source register)
//      Branch                 -> RD field (compare RS vs RD)
//      default                -> RT field
//
//  Data-memory address routing:
//    write_addr: PUSH -> RPI+1 | STORER -> ReadData1(RS) | others -> ALUResult
//    read_addr : POP  -> ReadData1(RPI)  | LOADR -> ReadData1(RS) | others -> ALUResult
// =============================================================================

module Processador (
    input  wire        clk,
    input  wire        en,    // clock-enable: 1 runs one step, 0 freezes state
    input  wire        rst,

    input  wire [31:0] Switches,
    output wire [31:0] Display,

    // ── DEBUG taps (for waveform / status LEDs) ────────────────────────────────
    output wire [31:0] dbg_PC,
    output wire [31:0] dbg_instruction,
    output wire [5:0]  dbg_opcode,

    output wire [31:0] dbg_ReadData1,
    output wire [31:0] dbg_ReadData2,
    output wire [31:0] dbg_immediate,

    output wire [31:0] dbg_ALUResult,
    output wire [31:0] dbg_MemData,

    output wire        dbg_Zero,
    output wire        dbg_Negative,

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

    // Opcode constants used by the muxing below.
    localparam MOV_OP    = 6'b010000;
    localparam MOVI_OP   = 6'b010001;
    localparam LOADR_OP  = 6'b010010;
    localparam LOADI_OP  = 6'b010100;
    localparam STORER_OP = 6'b010101;
    localparam STOREI_OP = 6'b010111;

    // =========================================================================
    //  Control signals (from the control unit)
    // =========================================================================
    wire        RegWrite, RHWrite, RPIWrite, RALWrite;
    wire        ULASource;
    wire [3:0]  ULAControl;
    wire        MemRead, MemWrite, MemToReg;
    wire        Branch;
    wire [1:0]  BranchCond;
    wire        Jump, JR, HLT;
    wire        Push, Pop, StackOp;
    wire        InEnable, OutEnable;
    wire [1:0]  imm_sel;

    // =========================================================================
    //  Internal datapath wires
    // =========================================================================
    wire [31:0] PC_out;
    wire [31:0] immediate;
    wire [31:0] ReadData1, ReadData2;
    wire [31:0] ALUResult, ALUResultHigh;
    wire [31:0] WriteData;
    wire [31:0] MemData;
    wire        Zero, Negative;

    // =========================================================================
    //  Register-address muxing
    // =========================================================================

    // ReadReg1 -> ReadData1 -> ALU operand A
    wire [5:0] ReadReg1 =
        JR                  ? RD_field :   // JR: target is RD field
        (Push | Pop)        ? 6'd63    :   // PUSH/POP: read RPI (R63)
        (opcode == MOV_OP    ||
         opcode == MOVI_OP   ||
         opcode == LOADI_OP  ||
         opcode == STOREI_OP) ? 6'd0   :   // I* / MOV: A = RZ = 0
        RS_field;                           // default: RS

    // ReadReg2 -> ReadData2 -> ALU operand B or store data
    wire [5:0] ReadReg2 =
        (MemWrite | Push)   ? RD_field :   // STORE/PUSH: read RD (data to store)
        (opcode == MOV_OP)  ? RS_field :   // MOV: B = RS (A = RZ, result = RS)
        Branch              ? RD_field :   // Branch: compare RS vs RD (Type I has no RT)
        RT_field;                           // default: RT

    // =========================================================================
    //  Branch condition evaluation
    // =========================================================================
    wire BranchTaken = Branch && (
        (BranchCond == 2'b00) ?  Zero               :   // BEQ: Zero = 1
        (BranchCond == 2'b01) ? ~Zero               :   // BNE: Zero = 0
        (BranchCond == 2'b10) ?  Negative           :   // BLT: Neg = 1
                                 (~Negative & ~Zero)     // BGT: Neg = 0 & Zero = 0
    );

    // =========================================================================
    //  ALU operand B mux (register vs immediate)
    // =========================================================================
    wire [31:0] ALU_B = ULASource ? immediate : ReadData2;

    // =========================================================================
    //  Register write-data mux
    //    Priority: InEnable (IN) > MemToReg (LOAD) > ALUResult (ALU)
    // =========================================================================
    assign WriteData = InEnable ? Switches :
                       MemToReg ? MemData  :
                       ALUResult;

    // =========================================================================
    //  Stack pointer (RPI) update for PUSH / POP
    //    ReadData1 = current RPI (ReadReg1 = R63 for Push/Pop)
    // =========================================================================
    wire [31:0] RPI_val = ReadData1;
    wire [31:0] RPI_new = Push ? RPI_val + 32'd1 : RPI_val - 32'd1;

    // =========================================================================
    //  Data-memory address routing
    // =========================================================================
    wire [5:0] mem_write_addr =
        Push                    ? RPI_new[5:0]   :   // PUSH: pre-incremented RPI
        (opcode == STORER_OP)   ? ReadData1[5:0] :   // STORER: address = RS (bypass ALU)
        ALUResult[5:0];                               // STORED/STOREI: RS+END14 or END20

    wire [5:0] mem_read_addr =
        Pop                     ? RPI_val[5:0]   :   // POP: current RPI
        (opcode == LOADR_OP)    ? ReadData1[5:0] :   // LOADR: address = RS (bypass ALU)
        ALUResult[5:0];                               // LOADD/LOADI: RS+END14 or END20

    wire [31:0] mem_data_in = ReadData2;             // STORE/PUSH data = RD value (muxed)

    // =========================================================================
    //  RAL: return address (next instruction) saved before a JAL jump.
    //    Must be PC+1 — saving PC_out would return to the JAL itself (loop).
    // =========================================================================
    wire [31:0] RAL_in = PC_out + 32'd1;

    // =========================================================================
    //  Display output (OUT) — shows the value AT the OUT and holds it afterwards
    //    - During an OUT: Display = ReadData1 (combinational) -> appears exactly
    //      on the OUT instruction being executed.
    //    - Otherwise (and on HLT): holds the last shown value (disp_hold), so it
    //      does not flicker between instructions and does not blank on halt.
    //    - rst clears it to 0.
    // =========================================================================
    reg [31:0] disp_hold;
    always @(negedge clk or posedge rst) begin
        if (rst)
            disp_hold <= 32'b0;
        else if (en && OutEnable)
            disp_hold <= ReadData1;      // latch the current OUT value
    end
    assign Display = (en && OutEnable) ? ReadData1 : disp_hold;

    // =========================================================================
    //  Module instantiations   (port  <-  connected signal)
    // =========================================================================

    // ── Program Counter ─────────────────────────────────────────────────────
    PC pc (
        .clk          (clk),
        .rst          (rst),
        .en           (en),               // freeze until armed
        .HLT          (HLT),
        .Jump         (Jump),
        .JR           (JR),
        .Branch       (BranchTaken),
        .JumpAddr     (immediate),        // END26 sign-extended
        .BranchOffset (immediate),        // END14 sign-extended
        .JRAddr       (ReadData1),        // RD register (ReadReg1 = RD for JR)
        .PC_out       (PC_out)
    );

    // ── Instruction Memory (ROM) ────────────────────────────────────────────
    MemInstrucao rom (
        .addr (PC_out[6:0]),
        .q    (instruction)
    );

    // ── Control Unit ────────────────────────────────────────────────────────
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
        .StackOp    (StackOp),
        .InEnable   (InEnable),
        .OutEnable  (OutEnable),
        .imm_sel    (imm_sel)
    );

    // ── Immediate Extractor ─────────────────────────────────────────────────
    Extensor ext (
        .instruction (instruction),
        .imm_sel     (imm_sel),
        .immediate   (immediate)
    );

    // ── ALU ─────────────────────────────────────────────────────────────────
    ULA ula (
        .A          (ReadData1),
        .B          (ALU_B),
        .ALUControl (ULAControl),
        .Result     (ALUResult),
        .ResultHigh (ALUResultHigh),
        .Zero       (Zero),
        .Negative   (Negative)
    );

    // ── Register Bank ───────────────────────────────────────────────────────
    //  Write enables are gated with `en` so nothing is written until armed.
    BancoRegistradores banco (
        .clk        (clk),
        .rst        (rst),
        .ReadReg1   (ReadReg1),
        .ReadReg2   (ReadReg2),
        .ReadData1  (ReadData1),
        .ReadData2  (ReadData2),
        .RegWrite   (RegWrite & en),
        .WriteReg   (RD_field),
        .WriteData  (WriteData),
        .RHWrite    (RHWrite  & en),
        .RH         (ALUResultHigh),
        .RPIWrite   (RPIWrite & en),
        .RPI        (RPI_new),
        .RALWrite   (RALWrite & en),
        .RAL        (RAL_in)
    );

    // ── Data Memory (RAM) ───────────────────────────────────────────────────
    MemDados ram (
        .write_clk  (clk),
        .read_clk   (clk),
        .MemWrite   (MemWrite & en),
        .write_addr (mem_write_addr),
        .read_addr  (mem_read_addr),
        .data_in    (mem_data_in),
        .data_out   (MemData)
    );

    // =========================================================================
    //  DEBUG taps
    // =========================================================================
    assign dbg_PC          = PC_out;
    assign dbg_instruction = instruction;
    assign dbg_opcode      = opcode;
    assign dbg_ReadData1   = ReadData1;
    assign dbg_ReadData2   = ReadData2;
    assign dbg_immediate   = immediate;
    assign dbg_ALUResult   = ALUResult;
    assign dbg_MemData     = MemData;
    assign dbg_Zero        = Zero;
    assign dbg_Negative    = Negative;
    assign dbg_RegWrite    = RegWrite;
    assign dbg_MemRead     = MemRead;
    assign dbg_MemWrite    = MemWrite;
    assign dbg_HLT         = HLT;
    assign dbg_BranchTaken = BranchTaken;

endmodule
