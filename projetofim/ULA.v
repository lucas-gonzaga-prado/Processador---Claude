`timescale 1ns / 1ps

// =============================================================================
//  ULA — Arithmetic Logic Unit
//
//  Combinational. Computes Result (and ResultHigh for MUL/DIV) from operands
//  A and B according to ALUControl, and exposes the Zero and Negative flags
//  used by the branch logic.
//
//  ALUControl:
//    0000 ADD   0001 SUB   0010 AND   0011 OR
//    0100 NOR   0101 XNOR  0110 SLL   0111 SRL (arithmetic)
//    1000 MUL   1001 DIV
// =============================================================================

module ULA (
    input  wire [31:0] A,
    input  wire [31:0] B,
    input  wire [3:0]  ALUControl,

    output reg  [31:0] Result,       // main result (low word for MUL/DIV)
    output reg  [31:0] ResultHigh,   // MUL: high word | DIV: remainder
    output wire        Zero,         // Result == 0
    output wire        Negative      // Result[31] (sign bit)
);

    reg [63:0] mult_result;

    always @(*) begin
        Result      = 32'b0;
        ResultHigh  = 32'b0;
        mult_result = 64'b0;

        case (ALUControl)
            4'b0000: Result = A + B;                  // ADD
            4'b0001: Result = A - B;                  // SUB

            4'b0010: Result = A & B;                  // AND
            4'b0011: Result = A | B;                  // OR
            4'b0100: Result = ~(A | B);               // NOR
            4'b0101: Result = ~(A ^ B);               // XNOR

            4'b0110: Result = A << B[4:0];            // shift left logical
            4'b0111: Result = $signed(A) >>> B[4:0];  // shift right arithmetic

            4'b1000: begin                            // MUL (signed, 64-bit product)
                mult_result = $signed(A) * $signed(B);
                Result     = mult_result[31:0];
                ResultHigh = mult_result[63:32];
            end

            4'b1001: begin                            // DIV (signed): quotient + remainder
                if (B != 32'b0) begin
                    Result     = $signed(A) / $signed(B);
                    ResultHigh = $signed(A) % $signed(B);
                end else begin                        // divide-by-zero guard
                    Result     = 32'hFFFFFFFF;
                    ResultHigh = 32'hFFFFFFFF;
                end
            end

            default: begin
                Result     = 32'b0;
                ResultHigh = 32'b0;
            end
        endcase
    end

    assign Zero     = (Result == 32'b0) ? 1'b1 : 1'b0;
    assign Negative = Result[31];

endmodule
