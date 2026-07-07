`timescale 1ns / 1ps

// =============================================================================
//  projetofinal — Top-level I/O for the DE2-115 (Cyclone IV EP4CE115F29C7)
//
//  Board mapping:
//    CLOCK_50    -> 50 MHz reference clock (divided down to clk_slow)
//    KEY[0]      -> reset (active-low) — returns to the idle state (PC=0, display 0)
//    KEY[1]      -> start (active-low) — one press arms; then it runs on its own
//    SW[17:0]    -> Switches[17:0] input (read by the IN instruction)
//    LEDR[17:0]  -> Display[17:0] in binary (OUT value, low 18 bits)
//    LEDG[0]     -> running (on while executing, off when idle or halted)
//    LEDG[1]     -> MemWrite active     LEDG[2] -> MemRead active
//    LEDG[3]     -> branch taken
//    HEX0-HEX7   -> Display in DECIMAL (via bin2bcd): HEX0=units, HEX1=tens, ...
//                   (values >= 10^8 show only the low 8 decimal digits)
//
//  Behaviour: on power-up/reset the core is frozen (PC=0, display 0). One press
//  of KEY[1] arms it (started=1); from then on it runs automatically on clk_slow
//  until HLT. The display holds the last shown value (does not blank on HLT).
// =============================================================================

module projetofinal (
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,        // active-low
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

    // ── Internal wires ──────────────────────────────────────────────────────────
    wire        rst;
    wire [31:0] Switches;
    wire [31:0] Display;

    wire        clk_slow;      // divided processor clock
    wire        start_pulse;   // one-shot strobe from the start button (KEY[1])

    reg         started;       // 0 = idle (display 0), 1 = running

    // Status taps exposed by the core (drive the green LEDs).
    wire        HLT_sig;
    wire        MemWrite_sig;
    wire        MemRead_sig;
    wire        BranchTaken_sig;

    // ── Reset: KEY[0] active-low -> rst active-high ─────────────────────────────
    assign rst = ~KEY[0];

    // ── Switches: SW[17:0] -> Switches[17:0], upper bits = 0 ────────────────────
    assign Switches = {14'b0, SW[17:0]};

    // ── Slow clock + button debounce ────────────────────────────────────────────
    // Divider: clk_slow = 50MHz / (2*DIVISOR).
    DivisorFreq #(
        .DIVISOR(50000000) // 0.5 Hz: one instruction every 2 s (long test, easy to follow)
    ) div_clock (
        .clk_in  (CLOCK_50),
        .clk_out (clk_slow)
    );

    // Start button (KEY[1]) debounced into a clean one-shot strobe.
    botao btn_start (
        .clk    (clk_slow),
        .btn_n  (KEY[1]),
        .pulse  (start_pulse)
    );

    // ── Start gate: one press arms, then it runs on its own ─────────────────────
    // 'started' rises on the first KEY[1] press (rising edge of start_pulse) and
    // feeds the core's clock-enable. KEY[0] (reset) clears it back to idle.
    initial started = 1'b0;
    always @(posedge start_pulse or posedge rst) begin
        if (rst) started <= 1'b0;   // reset -> idle
        else     started <= 1'b1;   // first press -> run automatically
    end

    // ── Processor core ──────────────────────────────────────────────────────────
    // Clocked by the free-running clk_slow; 'started' drives the clock-enable so
    // the core stays frozen (PC=0) until armed.
    Processador proc (
        .clk             (clk_slow),      // port clk        <- clk_slow
        .en              (started),       // port en         <- started (arm)
        .rst             (rst),
        .Switches        (Switches),
        .Display         (Display),

        .dbg_MemWrite    (MemWrite_sig),
        .dbg_MemRead     (MemRead_sig),
        .dbg_HLT         (HLT_sig),
        .dbg_BranchTaken (BranchTaken_sig)
    );

    // ── LEDs ────────────────────────────────────────────────────────────────────
    assign LEDR[17:0] = Display[17:0];        // OUT value in binary

    assign LEDG[0]   = started & ~HLT_sig;    // running
    assign LEDG[1]   = MemWrite_sig;          // writing to memory
    assign LEDG[2]   = MemRead_sig;           // reading from memory
    assign LEDG[3]   = BranchTaken_sig;       // branch taken
    assign LEDG[8:4] = 5'b0;                  // unused

    // ── Seven-segment displays: Display shown in DECIMAL ────────────────────────
    // bin2bcd converts the binary value to 8 BCD digits (double dabble); each
    // digit drives one 7-segment display. Values >= 10^8 show the low 8 digits.
    wire [31:0] bcd;
    bin2bcd conv (.bin(Display), .bcd(bcd));

    hex_decoder h0 (.val(bcd[3:0]),   .seg(HEX0));   // units
    hex_decoder h1 (.val(bcd[7:4]),   .seg(HEX1));   // tens
    hex_decoder h2 (.val(bcd[11:8]),  .seg(HEX2));   // hundreds
    hex_decoder h3 (.val(bcd[15:12]), .seg(HEX3));
    hex_decoder h4 (.val(bcd[19:16]), .seg(HEX4));
    hex_decoder h5 (.val(bcd[23:20]), .seg(HEX5));
    hex_decoder h6 (.val(bcd[27:24]), .seg(HEX6));
    hex_decoder h7 (.val(bcd[31:28]), .seg(HEX7));

endmodule


// =============================================================================
//  bin2bcd — binary -> BCD converter ("double dabble", combinational)
//
//  Input: 32-bit binary. Output: 8 BCD digits (4 bits each = 0..9), one per
//  7-segment display, so the number reads in DECIMAL. Only 8 displays exist, so
//  values >= 100,000,000 show just the low 8 decimal digits.
// =============================================================================

module bin2bcd (
    input  wire [31:0] bin,
    output reg  [31:0] bcd    // bcd[3:0]=units, [7:4]=tens, ...
);
    integer i, j;
    always @(*) begin
        bcd = 32'd0;
        for (i = 31; i >= 0; i = i - 1) begin
            // Before shifting, add 3 to any BCD digit that is >= 5.
            for (j = 0; j < 8; j = j + 1)
                if (bcd[j*4 +: 4] >= 5)
                    bcd[j*4 +: 4] = bcd[j*4 +: 4] + 4'd3;
            // Shift left by one, bringing in the next binary bit.
            bcd = {bcd[30:0], bin[i]};
        end
    end
endmodule


// =============================================================================
//  hex_decoder — 4-bit value to 7-segment display (active-low)
//    Bit order: seg[6:0] = gfedcba   (0 = segment ON, 1 = segment OFF)
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
