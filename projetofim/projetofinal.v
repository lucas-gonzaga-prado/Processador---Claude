`timescale 1ns / 1ps

// =============================================================================
//  Top.v — Top-level IO for DE2-115 (Cyclone IV EP4CE115F29C7)
//
//  Pin mapping:
//    CLOCK_50     → processor clock (50 MHz)
//    KEY[0]       → reset (active low) — volta ao estado inicial (PC=0, display 0000)
//    KEY[1]       → start (1 aperto inicia; depois roda sozinho no clk_lento)
//
//  Estado inicial: ao ligar/resetar, o processador fica congelado (PC=0) e o
//  display mostra "0000". Basta 1 aperto de KEY[1] para iniciar; a partir dai o
//  programa roda automaticamente (~10 Hz) ate o HLT. O display TRAVA no ultimo
//  valor mostrado (nao apaga no HLT). KEY[0] reinicia tudo.
//    SW[17:0]     → Switches[17:0] input (IN instruction)
//    LEDR[17:0]   → Display[17:0]  output (OUT instruction)
//    LEDG[8:0]    → status LEDs
//                   LEDG[0] = processor running (HLT indicator)
//                   LEDG[1] = MemWrite active
//                   LEDG[2] = MemRead active
//                   LEDG[3] = Branch taken
//    HEX0-HEX7   → Display em DECIMAL (via bin2bcd): HEX0=unidades, HEX1=dezenas,
//                   HEX2=centenas, ... (valores >= 10^8 mostram os 8 dígitos baixos)
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
    
    // Instancia o divisor de frequência: 50MHz / (2*DIVISOR) = 1 MHz
    DivisorFreq #(
        .DIVISOR(25)       // 1 MHz: Fibonacci roda quase instantaneo (mostra so o resultado)
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

    // ── Start gate: 1 aperto inicia; depois roda SOZINHO ───────────────────────
    // 'started' sobe no 1º aperto do KEY[1] (borda de subida do clock_passo).
    // Depois disso o processador roda automaticamente no clock livre clk_lento
    // (~10 Hz) — nao precisa apertar a cada instrucao.
    // KEY[0] (reset) volta 'started' a 0 (tela inicial 0000) para rodar de novo.
    initial started = 1'b0;
    always @(posedge clock_passo or posedge rst) begin
        if (rst) started <= 1'b0;   // KEY[0] reinicia (tela inicial 0000)
        else     started <= 1'b1;   // 1º aperto libera a execucao automatica
    end

    // ── Processor instantiation ────────────────────────────────────────────────
    // Clock LIVRE: o processador roda no clk_lento (clock limpo do divisor, ja em
    // rede global). 'started' entra como CLOCK-ENABLE (en): enquanto 0 o PC e as
    // escritas ficam congelados (PC=0). O 1º aperto do KEY[1] arma (started=1) e a
    // partir dai o clk_lento avanca uma instrucao por borda automaticamente ate o HLT.
    Processador proc (
        .clk             (clk_lento),   // clock livre ~10 Hz (roda sozinho)
        .en              (started),     // 1º aperto arma; depois roda automatico
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

    // ── Seven-segment displays: mostra Display em DECIMAL (8 dígitos) ───────────
    // Converte o valor binário para BCD (double dabble) e manda cada dígito
    // decimal (0..9) para um display. Valores >= 10^8 mostram os 8 dígitos baixos.
    wire [31:0] bcd;
    bin2bcd conv (.bin(Display), .bcd(bcd));

    hex_decoder h0 (.val(bcd[3:0]),   .seg(HEX0));   // unidades
    hex_decoder h1 (.val(bcd[7:4]),   .seg(HEX1));   // dezenas
    hex_decoder h2 (.val(bcd[11:8]),  .seg(HEX2));   // centenas
    hex_decoder h3 (.val(bcd[15:12]), .seg(HEX3));
    hex_decoder h4 (.val(bcd[19:16]), .seg(HEX4));
    hex_decoder h5 (.val(bcd[23:20]), .seg(HEX5));
    hex_decoder h6 (.val(bcd[27:24]), .seg(HEX6));
    hex_decoder h7 (.val(bcd[31:28]), .seg(HEX7));

endmodule


// =============================================================================
//  bin2bcd — conversor binário -> BCD (algoritmo "double dabble", combinacional)
//
//  Entrada: 32 bits binário.  Saída: 8 dígitos BCD (4 bits cada = 0..9).
//  Cada dígito vai para um display de 7 segmentos, mostrando o número em DECIMAL.
//  Observação: só há 8 displays, então valores >= 100.000.000 mostram apenas os
//  8 dígitos decimais mais baixos (o resto do range de 32 bits não cabe).
// =============================================================================

module bin2bcd (
    input  wire [31:0] bin,
    output reg  [31:0] bcd    // 8 dígitos: bcd[3:0]=unidades, [7:4]=dezenas, ...
);
    integer i, j;
    always @(*) begin
        bcd = 32'd0;
        for (i = 31; i >= 0; i = i - 1) begin
            // antes de deslocar, soma 3 a cada dígito BCD que for >= 5
            for (j = 0; j < 8; j = j + 1)
                if (bcd[j*4 +: 4] >= 5)
                    bcd[j*4 +: 4] = bcd[j*4 +: 4] + 4'd3;
            // desloca 1 bit para a esquerda, trazendo o próximo bit do binário
            bcd = {bcd[30:0], bin[i]};
        end
    end
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