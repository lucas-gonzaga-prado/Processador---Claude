`timescale 1ns / 1ps

module ULA (
    input  wire [31:0] A,
    input  wire [31:0] B,
    input  wire [3:0]  ALUControl,
    
    output reg  [31:0] Result,
    output reg  [31:0] Result_High,
    output wire        Zero,
    output wire        Negativo
);

    reg [63:0] mult_result;

	 always @(*) begin
        Result      = 32'b0;
        Result_High = 32'b0;
        mult_result = 64'b0;
		  
        case (ALUControl)

            4'b0000: Result = A + B;

            4'b0001: Result = A - B;

            4'b0010: Result = A & B;
            4'b0011: Result = A | B;
            4'b0100: Result = ~(A | B);
            4'b0101: Result = ~(A ^ B);

            4'b0110: Result = A << B[4:0];
            4'b0111: Result = $signed(A) >>> B[4:0];

            4'b1000: begin
                mult_result = $signed(A) * $signed(B);
                Result      = mult_result[31:0];
                Result_High = mult_result[63:32];
            end

            4'b1001: begin
                if (B != 32'b0) begin
                    Result      = $signed(A) / $signed(B);
                    Result_High = $signed(A) % $signed(B);
                end else begin
                    Result      = 32'hFFFFFFFF;
                    Result_High = 32'hFFFFFFFF;
                end
            end

            default: begin
                Result      = 32'b0;
                Result_High = 32'b0;
            end
        endcase
    end

    assign Zero     = (Result == 32'b0) ? 1'b1 : 1'b0;
    assign Negativo = Result[31];

endmodule