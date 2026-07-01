; =============================================================================
;  fibonacci.asm — sequencia de Fibonacci (0, 1, 1, 2, 3, ...)
;
;  Monta com:   perl asm.pl fibonacci.asm instrucoes.txt
;
;  QUANTIDADE DE TERMOS vem das chaves SW (em binario): ajuste as chaves para o
;  numero desejado, aperte KEY[1] para rodar e KEY[0] para resetar.
;  Ex.: SW = 001001 (9) -> mostra 0,1,1,2,3,5,8,13,21 (display em hex: ...8, d, 15).
;  O valor final fica TRAVADO no display ao chegar no HLT.
;  (SW = 0 -> 0 termos; display fica em 0.)
;
;  Registradores:  R1 = contador   R3 = a (atual)   R4 = b (proximo)   R5 = temporario
; =============================================================================

        IN   R1             ; contador = valor das chaves SW (binario)
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
