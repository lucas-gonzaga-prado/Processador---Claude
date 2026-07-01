; =============================================================================
;  teste_completo.asm — exercita TODAS as 37 instrucoes do processador
;
;  Monta com:   perl asm.pl teste_completo.asm instrucoes.txt
;
;  Base: R1 = 12 (0x0C), R2 = 4. R0 = 0 sempre. R30 = marcador de FALHA.
;  A cada aperto do botao o processador avanca uma instrucao; nos OUT o valor
;  aparece no display de 7 segmentos. Sequencia esperada (so os OUT):
;    000C 0010 0008 0030 0003 000F 0007 0014 0002 0004 000C FFFFFFF3 FFFFFFF7
;    0004 000F 0030 0006 000C 000C 0010 0008 000F  (branches)  005B BACC 0155
;  LEDG1=MemWrite, LEDG2=MemRead, LEDG3=BranchTaken, LEDG0 apaga no HLT.
;  Se aparecer 0000FA11 em algum passo -> um branch falhou.
; =============================================================================

; ---- setup ----
        MOVI R1, 12          ; R1 = 12
        MOVI R2, 4           ; R2 = 4
        MOVI R30, 0xFA11     ; marcador de FALHA
        OUT  R1              ; 0000000C   (MOVI + OUT)

; ---- aritmetica registrador ----
        ADD  R3, R1, R2      ; 16
        OUT  R3              ; 00000010   ADD
        SUB  R4, R1, R2      ; 8
        OUT  R4              ; 00000008   SUB
        MUL  R5, R1, R2      ; 48   (R61 = 0)
        OUT  R5              ; 00000030   MUL
        DIV  R6, R1, R2      ; 3    (R61 = 0)
        OUT  R6              ; 00000003   DIV

; ---- aritmetica imediata ----
        ADDI R7, R1, 3       ; 15
        OUT  R7              ; 0000000F   ADDI
        SUBI R8, R1, 5       ; 7
        OUT  R8              ; 00000007   SUBI
        MULI R9, R2, 5       ; 20
        OUT  R9              ; 00000014   MULI
        DIVI R10, R1, 5      ; 2    (R61 = 2)
        OUT  R10             ; 00000002   DIVI

; ---- logica ----
        AND  R11, R1, R2     ; 4
        OUT  R11             ; 00000004   AND
        OR   R12, R1, R2     ; 12
        OUT  R12             ; 0000000C   OR
        NOR  R13, R1, R2     ; ~(12|4) = FFFFFFF3
        OUT  R13             ; FFFFFFF3   NOR
        XNOR R14, R1, R2     ; ~(12^4) = FFFFFFF7
        OUT  R14             ; FFFFFFF7   XNOR
        ANDI R15, R1, 6      ; 4
        OUT  R15             ; 00000004   ANDI
        ORI  R16, R1, 3      ; 15
        OUT  R16             ; 0000000F   ORI

; ---- shift ----
        SL   R17, R1, 2      ; 12 << 2 = 48
        OUT  R17             ; 00000030   SL
        SR   R18, R1, 1      ; 12 >> 1 = 6
        OUT  R18             ; 00000006   SR

; ---- move ----
        MOV  R19, R1         ; 12
        OUT  R19             ; 0000000C   MOV

; ---- memoria: enderecamento imediato ----
        STOREI R1, 10        ; MEM[10] = 12    (LEDG1)
        LOADI  R20, 10       ; R20 = MEM[10]   (LEDG2)
        OUT    R20           ; 0000000C   STOREI+LOADI

; ---- memoria: enderecamento por registrador ----
        STORER R3, R2        ; MEM[R2=4] = R3=16
        LOADR  R21, R2       ; R21 = MEM[4] = 16
        OUT    R21           ; 00000010   STORER+LOADR

; ---- memoria: enderecamento com deslocamento ----
        STORED R4, R2, 8     ; MEM[R2+8=12] = R4=8
        LOADD  R22, R2, 8    ; R22 = MEM[12] = 8
        OUT    R22           ; 00000008   STORED+LOADD

; ---- pilha ----
        MOVI R63, 30         ; RPI = 30
        PUSH R7              ; MEM[31] = R7=15, RPI=31   (LEDG1)
        POP  R23             ; R23 = MEM[31] = 15, RPI=30 (LEDG2)
        OUT  R23             ; 0000000F   PUSH+POP

; ---- branches (todos TOMADOS -> LEDG3 acende; pulam o OUT de falha) ----
        BEQ  R2, R2, Lbeq    ; 4 == 4  -> tomado
        OUT  R30             ; FALHA (nunca deve executar)
Lbeq:   BNE  R1, R2, Lbne    ; 12 != 4 -> tomado
        OUT  R30             ; FALHA
Lbne:   BLT  R2, R1, Lblt    ; 4 < 12  -> tomado
        OUT  R30             ; FALHA
Lblt:   BGT  R1, R2, Lbgt    ; 12 > 4  -> tomado
        OUT  R30             ; FALHA
Lbgt:   NOP                  ; NOP

; ---- jump incondicional + sub-rotina (JMP, JAL, JR) ----
        JMP  Lmain           ; pula por cima do corpo da sub-rotina
Lsub:   MOVI R24, 0x5B       ; marcador "dentro da sub"
        OUT  R24             ; 0000005B   entrou na sub (via JAL)
        JR   R62             ; retorna (R62 = endereco apos o JAL)
Lmain:  JAL  Lsub            ; R62 = proximo endereco, chama a sub
        MOVI R26, 0xBACC     ; marcador "voltou"
        OUT  R26             ; 0000BACC   retornou (JAL+JR ok)

; ---- entrada (le as chaves SW) ----
        IN   R40             ; R40 = valor das chaves SW
        OUT  R40             ; mostra as chaves (ex.: ponha SW = 0x155)

; ---- fim ----
        HLT                  ; LEDG0 apaga
