`timescale 1ns / 1ps

// =============================================================================
//  Top.v — Top-level IO for DE2-115 (Cyclone IV EP4CE115F29C7)
//
//  Pin mapping:
//    CLOCK_50     → processor clock (50 MHz)
//    KEY[0]       → reset (active low) — volta ao estado travado
//    KEY[1]       → step button (avança o clock do processador manualmente)
//
//  Estado inicial: ao ligar/resetar, o processador fica travado (PC=0) e os
//  displays mostram "0000". O 1º aperto de KEY[1] libera o sistema (continua 0000).
//  A partir do 2º aperto, cada toque executa uma instrução (modo passo a passo).
//    SW[17:0]     → Switches[17:0] input (IN instruction)
//    LEDR[17:0]   → Display[17:0]  output (OUT instruction)
//    LEDG[8:0]    → status LEDs
//                   LEDG[0] = processor running (HLT indicator)
//                   LEDG[1] = MemWrite active
//                   LEDG[2] = MemRead active
//                   LEDG[3] = Branch taken
//    HEX0-HEX7   → Display[31:0] shown as 8 hex digits
//                   HEX7 HEX6 HEX5 HEX4 | HEX3 HEX2 HEX1 HEX0
//                   [31:28][27:24][23:20][19:16] [15:12][11:8][7:4][3:0]
// =============================================================================

module projetofinal (
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,        // active low
    input  wire [17:0] SW,

    output wire [17:0] LEDR,
    output wire [8:0]  LEDG,
    output wire [6:0]  HEX0,
    output wire [6:0]  HEX1,
    output wire [6:0]  HEX2,
    output wire [6:0]  HEX3,
    output wire [6:0]  HEX4,
    output wire [6:0]  HEX5,
    output wire [6:0]  HEX6,
    output wire [6:0]  HEX7
);

    // ── Internal wires ─────────────────────────────────────────────────────────
    wire        rst;
    wire [31:0] Switches;
    wire [31:0] Display;
    
    wire        clk_lento;
    wire        clock_passo; // Sinal do botão para o processador

    reg         started;     // 0 = travado (display 0000), 1 = programa liberado

    // ── Control signals exposed from processor ─────────────────────────────────
    wire        HLT_sig;
    wire        MemWrite_sig;
    wire        MemRead_sig;
    wire        BranchTaken_sig;

    // ── Reset: KEY[0] active low → rst active high ─────────────────────────────
    assign rst = ~KEY[0];

    // ── Switches: SW[17:0] → Switches[17:0], upper bits = 0 ───────────────────
    assign Switches = {14'b0, SW[17:0]};

    // ── Geração de Clock Lento e Debounce do Botão ─────────────────────────────
    
    // Instancia o divisor de frequência (50MHz -> ~1Hz)
    DivisorFreq #(
        .DIVISOR(2500000) // Ajustado para ~10Hz para o botão responder mais rápido
    ) div_clock (
        .clk_in  (CLOCK_50),
        .clk_out (clk_lento)
    );

    // Instancia o botão para o modo Step (KEY[1])
    botao btn_step (
        .clk     (clk_lento),
        .btn_n   (KEY[1]),
        .BOTTON  (clock_passo)
    );

    // ── Start gate: tela inicial "9999" até o primeiro aperto ──────────────────
    // started sobe na BORDA DE SUBIDA do clock_passo (fim do 1º pulso do botão),
    // quando o sinal já voltou a 1. Assim o aperto que "arma" NÃO gera um negedge
    // no processador → ele não executa instrução nesse 1º toque, apenas libera.
    // A partir daí, cada aperto = um negedge = um passo do programa.
    initial started = 1'b0;
    always @(posedge clock_passo or posedge rst) begin
        if (rst) started <= 1'b0;   // KEY[0] volta para a tela inicial (9999)
        else     started <= 1'b1;   // 1º aperto libera o programa
    end

    // ── Processor instantiation ────────────────────────────────────────────────
    // Clock LIMPO: o processador é SEMPRE clocado por clock_passo (sem gated clock).
    // 'started' entra como CLOCK-ENABLE (en): enquanto 0, o PC e todas as escritas
    // ficam congelados (PC=0, Display=0000); o 1º aperto apenas arma (started↑ ocorre
    // na borda de subida, então o negedge desse 1º toque vê en=0 e não executa).
    // Isso substitui o antigo "started & clock_passo", que era um clock combinacional
    // e disparava o tempo de compilação no Quartus (gated clock → fit de horas).
    Processador proc (
        .clk             (clock_passo), // clock limpo (saída registrada do botão)
        .en              (started),     // habilita a execução só após o 1º aperto
        .rst             (rst),
        .Switches        (Switches),
        .Display         (Display),

        // Status signals → LEDs verdes
        .dbg_MemWrite    (MemWrite_sig),
        .dbg_MemRead     (MemRead_sig),
        .dbg_HLT         (HLT_sig),
        .dbg_BranchTaken (BranchTaken_sig)
    );

    // ── LEDs ───────────────────────────────────────────────────────────────────
    // Red LEDs: show lower 18 bits of Display
    assign LEDR[17:0] = Display[17:0];

    // Green LEDs: processor status
    assign LEDG[0] = started & ~HLT_sig; // ON = rodando, OFF = aguardando ou halt
    assign LEDG[1] = MemWrite_sig;     // ON = writing to memory
    assign LEDG[2] = MemRead_sig;      // ON = reading from memory
    assign LEDG[3] = BranchTaken_sig;  // ON = branch taken
    assign LEDG[8:4] = 5'b0;          // unused

    // ── Seven-segment displays: show Display[31:0] as 8 hex digits ─────────────
    // Enquanto travado (started=0) o processador fica em PC=0 e Display=0 → "0000".
    hex_decoder h0 (.val(Display[3:0]),   .seg(HEX0));
    hex_decoder h1 (.val(Display[7:4]),   .seg(HEX1));
    hex_decoder h2 (.val(Display[11:8]),  .seg(HEX2));
    hex_decoder h3 (.val(Display[15:12]), .seg(HEX3));
    hex_decoder h4 (.val(Display[19:16]), .seg(HEX4));
    hex_decoder h5 (.val(Display[23:20]), .seg(HEX5));
    hex_decoder h6 (.val(Display[27:24]), .seg(HEX6));
    hex_decoder h7 (.val(Display[31:28]), .seg(HEX7));

endmodule


// =============================================================================
//  hex_decoder — 4-bit value to 7-segment display (active low)
//
//  Segment layout:
//      _
//     |_|
//     |_|
//
//  Bit order: seg[6:0] = gfedcba
//  Active LOW: 0 = segment ON, 1 = segment OFF
// =============================================================================

module hex_decoder (
    input  wire [3:0] val,
    output reg  [6:0] seg
);
    always @(*) begin
        case (val)
            4'h0: seg = 7'b1000000; // 0
            4'h1: seg = 7'b1111001; // 1
            4'h2: seg = 7'b0100100; // 2
            4'h3: seg = 7'b0110000; // 3
            4'h4: seg = 7'b0011001; // 4
            4'h5: seg = 7'b0010010; // 5
            4'h6: seg = 7'b0000010; // 6
            4'h7: seg = 7'b1111000; // 7
            4'h8: seg = 7'b0000000; // 8
            4'h9: seg = 7'b0010000; // 9
            4'hA: seg = 7'b0001000; // A
            4'hB: seg = 7'b0000011; // B
            4'hC: seg = 7'b1000110; // C
            4'hD: seg = 7'b0100001; // D
            4'hE: seg = 7'b0000110; // E
            4'hF: seg = 7'b0001110; // F
            default: seg = 7'b1111111; // off
        endcase
    end
endmodule