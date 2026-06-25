`timescale 1ns / 1ps
// =============================================================================
//  Módulo BOTAO — Versão Corrigida (2 Clocks de Aceite + Saída Ativa em Baixo)
// =============================================================================
module botao (
    input  wire clk,       // clock do processador (já dividido)
    input  wire btn_n,     // botão físico — ativo em nível baixo (0 = pressionado)
    output reg  BOTTON     // pulso de 1 ciclo (ATUALIZADO: 0 = pulso de disparo)
);

    // Shift register reduzido para 2 bits (exige 2 amostras consecutivas)
    reg [1:0] shift;
    wire btn_ativo = ~btn_n;  // converte para ativo alto internamente

    // Garante que o sinal comece em 1 (já que agora o repouso é alto)
    initial begin
        shift  = 2'b00;
        BOTTON = 1'b1;
    end

    always @(posedge clk) begin
        shift <= {shift[0], btn_ativo};
    end

    // 1 apenas quando as 2 últimas amostras forem válidas (pressionado)
    wire btn_estavel = &shift;  

    reg btn_prev;
    always @(posedge clk) begin
        btn_prev <= btn_estavel;
        
        // INVERTIDO: O operador ~ garante que o sinal seja 1 por padrão.
        // No momento do clique, ele cai para 0 por 1 ciclo e faz o processador "pular".
        BOTTON   <= ~(btn_estavel & ~btn_prev);
    end

endmodule 