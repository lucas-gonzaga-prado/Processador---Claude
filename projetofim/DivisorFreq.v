`timescale 1ns / 1ps

// =============================================================================
//  DivisorFreq — Clock-frequency divider
//
//  Divides the 50 MHz board clock down to clk_out. The output toggles every
//  DIVISOR input cycles, so:  f(clk_out) = 50 MHz / (2 * DIVISOR).
//  DIVISOR is overridden at instantiation (e.g. 25 -> 1 MHz, 50_000_000 -> 0.5 Hz).
// =============================================================================

module DivisorFreq #(parameter DIVISOR = 25000000) (
    input      clk_in,     // 50 MHz board clock
    output reg clk_out     // divided clock
);
    reg [31:0] counter;

    initial begin
        counter = 0;
        clk_out = 0;
    end

    always @(posedge clk_in) begin
        if (counter == DIVISOR - 1) begin
            counter <= 0;
            clk_out <= ~clk_out;
        end else begin
            counter <= counter + 1;
        end
    end
endmodule
