`timescale 1ns / 1ps

// =============================================================================
//  botao — Push-button debounce + one-shot strobe
//
//  Filters the mechanical bounce of a physical push-button and produces a clean
//  single-cycle strobe. The output rests HIGH and drops to 0 for exactly one
//  clock cycle when a stable press is detected.
//
//  Sampled by the divided clock (clk_slow), so the response time scales with the
//  clock frequency (e.g. at 0.5 Hz it takes ~2 samples = a few seconds to accept).
// =============================================================================

module botao (
    input  wire clk,     // sampling clock (the divided clk_slow)
    input  wire btn_n,   // physical button, active-low (0 = pressed)
    output reg  pulse     // one-cycle strobe, idle-high (drops to 0 on a clean press)
);

    // 2-sample shift register: a press is accepted only after 2 consecutive samples.
    reg  [1:0] shift;
    wire btn_active = ~btn_n;   // convert to active-high internally

    // Start idle-high, since the output rests at 1.
    initial begin
        shift = 2'b00;
        pulse = 1'b1;
    end

    always @(posedge clk) begin
        shift <= {shift[0], btn_active};
    end

    // High only when the last 2 samples are both "pressed" (debounced).
    wire btn_stable = &shift;

    // Rising-edge detector: emit one strobe (pulse -> 0 for 1 cycle) at the moment
    // the button becomes stably pressed. The '~' keeps the output idle-high.
    reg btn_prev;
    always @(posedge clk) begin
        btn_prev <= btn_stable;
        pulse    <= ~(btn_stable & ~btn_prev);
    end

endmodule
