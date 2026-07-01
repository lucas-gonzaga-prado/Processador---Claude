; =============================================================================
;  fibonacci.asm — sequencia de Fibonacci (0, 1, 1, 2, 3, ...)
;
;  Monta com:   perl asm.pl fibonacci.asm instrucoes.txt
;
;  Mostra no display, a cada passo: 0, 1, 1, 2, 3  (contador = 5 termos).
;  Aumente o imediato do MOVI R1 para exibir mais termos (ex.: 7 -> ...5, 8).
;
;  Registradores:  R1 = contador   R3 = a (atual)   R4 = b (proximo)   R5 = temporario
; =============================================================================

        MOVI R1, 5          ; contador = 5 termos
        MOVI R3, 0          ; a = 0
        MOVI R4, 1          ; b = 1

Lloop:  BEQ  R0, R1, Lend   ; se contador == 0 -> fim
        OUT  R3             ; mostra o valor atual (a)
        MOV  R5, R3         ; tmp = a
        ADD  R3, R3, R4     ; a = a + b
        MOV  R4, R5         ; b = tmp (antigo a)
        SUBI R1, R1, 1      ; contador--
        JMP  Lloop          ; repete

Lend:   HLT                 ; para
