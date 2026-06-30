# =============================================================================
#  projetofinal.sdc — Timing constraints (DE2-115, Cyclone IV)
#
#  Objetivo: dar ao TimeQuest um clock base definido e modelar os clocks
#  derivados (divisor de frequência e botão de passo) como clocks GERADOS,
#  para o roteador parar de "adicionar atraso para fechar hold" sem constraint
#  (Critical Warning 332012 / mensagem de excesso de congestionamento).
#
#  Os clocks do processador são lentíssimos (passo manual ~Hz), então o
#  fechamento de tempo é trivial — o que falta é apenas declará-los.
# =============================================================================

# ── Clock base de 50 MHz (pino CLOCK_50) ────────────────────────────────────
create_clock -name CLOCK_50 -period 20.000 [get_ports CLOCK_50]

# ── Clock lento gerado pelo divisor de frequência ───────────────────────────
# DivisorFreq inverte clk_out a cada DIVISOR(=2.5M) ciclos → período = 5M ciclos.
create_generated_clock -name clk_lento \
    -source [get_ports CLOCK_50] -divide_by 5000000 \
    [get_registers {DivisorFreq:div_clock|clk_out}]

# ── Clock de passo (saída registrada do botão) — clock real do processador ──
# Derivado do clk_lento; modelado como /2 só para ter período definido.
create_generated_clock -name clock_passo \
    -source [get_registers {DivisorFreq:div_clock|clk_out}] -divide_by 2 \
    [get_registers {botao:btn_step|BOTTON}]

# ── Incertezas de clock ─────────────────────────────────────────────────────
derive_clock_uncertainty

# ── Entradas/saídas assíncronas (chaves, botões, LEDs, displays) ────────────
# Não há requisito de tempo real nesses caminhos (interface humana).
set_false_path -from [get_ports {KEY[*] SW[*]}] -to [all_registers]
set_false_path -from * -to [get_ports {LEDR[*] LEDG[*] HEX0[*] HEX1[*] HEX2[*] HEX3[*] HEX4[*] HEX5[*] HEX6[*] HEX7[*]}]
