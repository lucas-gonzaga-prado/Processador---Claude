`timescale 1ns / 1ps

// =============================================================================
//  ucontrole — Control Unit
//  Decodes the 6-bit opcode and generates every control signal (combinational).
//
//  Signal summary:
//    RegWrite    : enable write to a general register (RD)
//    RHWrite     : enable write to RH (R61) — MUL high word / DIV remainder
//    RPIWrite    : enable write to RPI (R63) — stack pointer update
//    RALWrite    : enable write to RAL (R62) — return address (JAL)
//    ULASource   : 0 = RT register,  1 = immediate
//    ULAControl  : ALU operation (4 bits)
//    MemRead     : enable data-memory read
//    MemWrite    : enable data-memory write
//    MemToReg    : 0 = ALU result,   1 = data-memory output
//    Branch      : branch instruction (conditional PC update)
//    BranchCond  : 00=BEQ, 01=BNE, 10=BLT, 11=BGT
//    Jump        : unconditional jump (JMP, JAL)
//    JR          : jump to register (JR)
//    HLT         : halt processor
//    Push        : PUSH operation
//    Pop         : POP operation
//    StackOp     : reserved stack flag (decoded for PUSH/POP, currently unused)
//    InEnable    : route the SWITCHES value to the register write data (IN)
//    OutEnable   : send a register value to the DISPLAY (OUT)
//    imm_sel     : 00=END14, 01=END20, 10=END26
// =============================================================================

module ucontrole (
    input  wire [5:0]  Opcode,

    output reg         RegWrite,
    output reg         RHWrite,
    output reg         RPIWrite,
    output reg         RALWrite,
    output reg         ULASource,
    output reg  [3:0]  ULAControl,
    output reg         MemRead,
    output reg         MemWrite,
    output reg         MemToReg,
    output reg         Branch,
    output reg  [1:0]  BranchCond,
    output reg         Jump,
    output reg         JR,
    output reg         HLT,
    output reg         Push,
    output reg         Pop,
    output reg         StackOp,
    output reg         InEnable,
    output reg         OutEnable,
    output reg  [1:0]  imm_sel
);

    // ── ALU operation constants ───────────────────────────────────────────────
    localparam ULA_ADD  = 4'b0000;
    localparam ULA_SUB  = 4'b0001;
    localparam ULA_AND  = 4'b0010;
    localparam ULA_OR   = 4'b0011;
    localparam ULA_NOR  = 4'b0100;
    localparam ULA_XNOR = 4'b0101;
    localparam ULA_SLL  = 4'b0110;
    localparam ULA_SRL  = 4'b0111;
    localparam ULA_MUL  = 4'b1000;
    localparam ULA_DIV  = 4'b1001;

    // ── Immediate selector constants ──────────────────────────────────────────
    localparam IMM14 = 2'b00;
    localparam IMM20 = 2'b01;
    localparam IMM26 = 2'b10;

    // ── Branch condition constants ────────────────────────────────────────────
    localparam BEQ_COND = 2'b00;  // branch if Zero = 1
    localparam BNE_COND = 2'b01;  // branch if Zero = 0
    localparam BLT_COND = 2'b10;  // branch if Neg  = 1
    localparam BGT_COND = 2'b11;  // branch if !Neg & !Zero

    // ── Opcode constants ──────────────────────────────────────────────────────
    localparam ADD    = 6'b000000;
    localparam ADDI   = 6'b000001;
    localparam SUB    = 6'b000010;
    localparam SUBI   = 6'b000011;
    localparam MUL    = 6'b000100;
    localparam MULI   = 6'b000101;
    localparam DIV    = 6'b000110;
    localparam DIVI   = 6'b000111;
    localparam AND_OP = 6'b001000;
    localparam ANDI   = 6'b001001;
    localparam OR_OP  = 6'b001010;
    localparam ORI    = 6'b001011;
    localparam NOR_OP = 6'b001100;
    localparam XNOR_OP= 6'b001101;
    localparam SL     = 6'b001110;
    localparam SR     = 6'b001111;
    localparam MOV    = 6'b010000;
    localparam MOVI   = 6'b010001;
    localparam LOADR  = 6'b010010;
    localparam LOADD  = 6'b010011;
    localparam LOADI  = 6'b010100;
    localparam STORER = 6'b010101;
    localparam STORED = 6'b010110;
    localparam STOREI = 6'b010111;
    localparam PUSH   = 6'b011000;
    localparam POP    = 6'b011001;
    localparam BEQ    = 6'b011010;
    localparam BNE    = 6'b011011;
    localparam BLT    = 6'b011100;
    localparam BGT    = 6'b011101;
    localparam JMP    = 6'b011110;
    localparam JAL    = 6'b011111;
    localparam JR_OP  = 6'b100000;
    localparam IN_OP  = 6'b100001;
    localparam OUT_OP = 6'b100010;
    localparam NOP    = 6'b100011;
    localparam HLT_OP = 6'b100100;

    // ── Combinational decode ──────────────────────────────────────────────────
    always @(*) begin

        // Default: every signal inactive.
        RegWrite   = 0;
        RHWrite    = 0;
        RPIWrite   = 0;
        RALWrite   = 0;
        ULASource  = 0;
        ULAControl = ULA_ADD;
        MemRead    = 0;
        MemWrite   = 0;
        MemToReg   = 0;
        Branch     = 0;
        BranchCond = BEQ_COND;
        Jump       = 0;
        JR         = 0;
        HLT        = 0;
        Push       = 0;
        Pop        = 0;
        StackOp    = 0;
        InEnable   = 0;
        OutEnable  = 0;
        imm_sel    = IMM14;

        case (Opcode)

            // ── Arithmetic — register ─────────────────────────────────────────
            ADD: begin RegWrite = 1; ULAControl = ULA_ADD; end
            SUB: begin RegWrite = 1; ULAControl = ULA_SUB; end
            MUL: begin RegWrite = 1; RHWrite = 1; ULAControl = ULA_MUL; end  // RD=low, R61=high
            DIV: begin RegWrite = 1; RHWrite = 1; ULAControl = ULA_DIV; end  // RD=quotient, R61=remainder

            // ── Arithmetic — immediate ────────────────────────────────────────
            ADDI: begin RegWrite = 1; ULASource = 1; ULAControl = ULA_ADD; end
            SUBI: begin RegWrite = 1; ULASource = 1; ULAControl = ULA_SUB; end
            MULI: begin RegWrite = 1; RHWrite = 1; ULASource = 1; ULAControl = ULA_MUL; end
            DIVI: begin RegWrite = 1; RHWrite = 1; ULASource = 1; ULAControl = ULA_DIV; end

            // ── Logic — register ──────────────────────────────────────────────
            AND_OP:  begin RegWrite = 1; ULAControl = ULA_AND;  end
            OR_OP:   begin RegWrite = 1; ULAControl = ULA_OR;   end
            NOR_OP:  begin RegWrite = 1; ULAControl = ULA_NOR;  end
            XNOR_OP: begin RegWrite = 1; ULAControl = ULA_XNOR; end

            // ── Logic — immediate ─────────────────────────────────────────────
            ANDI: begin RegWrite = 1; ULASource = 1; ULAControl = ULA_AND; end
            ORI:  begin RegWrite = 1; ULASource = 1; ULAControl = ULA_OR;  end

            // ── Shift (immediate amount) ──────────────────────────────────────
            SL: begin RegWrite = 1; ULASource = 1; ULAControl = ULA_SLL; end
            SR: begin RegWrite = 1; ULASource = 1; ULAControl = ULA_SRL; end

            // ── Data movement ─────────────────────────────────────────────────
            MOV: begin
                // RD <= RS: datapath sends RZ as A -> 0 + RS = RS
                RegWrite = 1; ULAControl = ULA_ADD;
            end
            MOVI: begin
                // RD <= IM20: A=RZ=0, B=IM20 -> 0 + IM20 = IM20
                RegWrite = 1; ULASource = 1; ULAControl = ULA_ADD; imm_sel = IMM20;
            end

            // ── Load ──────────────────────────────────────────────────────────
            LOADR: begin  // RD <= MEM[RS]
                RegWrite = 1; ULAControl = ULA_ADD; MemRead = 1; MemToReg = 1;
            end
            LOADD: begin  // RD <= MEM[RS + END14]
                RegWrite = 1; ULASource = 1; ULAControl = ULA_ADD; MemRead = 1; MemToReg = 1;
            end
            LOADI: begin  // RD <= MEM[END20]
                RegWrite = 1; ULASource = 1; ULAControl = ULA_ADD; MemRead = 1; MemToReg = 1; imm_sel = IMM20;
            end

            // ── Store ─────────────────────────────────────────────────────────
            STORER: begin  // MEM[RS] <= RD
                ULAControl = ULA_ADD; MemWrite = 1;
            end
            STORED: begin  // MEM[RS + END14] <= RD
                ULASource = 1; ULAControl = ULA_ADD; MemWrite = 1;
            end
            STOREI: begin  // MEM[END20] <= RD
                ULASource = 1; ULAControl = ULA_ADD; MemWrite = 1; imm_sel = IMM20;
            end

            // ── Stack ─────────────────────────────────────────────────────────
            PUSH: begin  // MEM[++RPI] <= RD
                RPIWrite = 1; ULAControl = ULA_ADD; MemWrite = 1; Push = 1; StackOp = 1;
            end
            POP: begin   // RD <= MEM[RPI--]
                RegWrite = 1; RPIWrite = 1; ULAControl = ULA_SUB; MemRead = 1; MemToReg = 1; Pop = 1; StackOp = 1;
            end

            // ── Branch (compare RS vs RD via SUB) ─────────────────────────────
            BEQ: begin ULAControl = ULA_SUB; Branch = 1; BranchCond = BEQ_COND; end
            BNE: begin ULAControl = ULA_SUB; Branch = 1; BranchCond = BNE_COND; end
            BLT: begin ULAControl = ULA_SUB; Branch = 1; BranchCond = BLT_COND; end
            BGT: begin ULAControl = ULA_SUB; Branch = 1; BranchCond = BGT_COND; end

            // ── Jump ──────────────────────────────────────────────────────────
            JMP: begin Jump = 1; imm_sel = IMM26; end
            JAL: begin RALWrite = 1; Jump = 1; imm_sel = IMM26; end  // RAL <= PC+1 (in the register bank)
            JR_OP: begin JR = 1; end

            // ── I/O ───────────────────────────────────────────────────────────
            IN_OP:  begin RegWrite = 1; InEnable  = 1; end  // RD <= SWITCHES
            OUT_OP: begin OutEnable = 1;               end  // DISPLAY <= RS

            // ── System ────────────────────────────────────────────────────────
            NOP:    begin /* no operation */ end
            HLT_OP: begin HLT = 1;           end

            default: begin /* undefined opcode: behaves as NOP */ end

        endcase
    end

endmodule
