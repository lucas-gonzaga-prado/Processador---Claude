#!/usr/bin/perl
# =============================================================================
#  asm.pl — Montador (assembler) do processador RISC custom (pasta projetofim)
# =============================================================================
#
#  O QUE FAZ
#  ---------
#  Converte um programa escrito em assembly LEGIVEL (arquivo .asm) para o
#  formato binario que a ROM (MemInstrucao.v) le com $readmemb: uma instrucao
#  de 32 bits ('0'/'1') por linha. A saida e exatamente o conteudo que vai
#  para "instrucoes.txt".
#
#  COMO USAR  (no Git Bash / terminal, com Perl instalado)
#  ---------
#      perl asm.pl  <entrada.asm>  <saida.txt>
#
#  Exemplos:
#      perl asm.pl teste_completo.asm instrucoes.txt
#      perl asm.pl fibonacci.asm      instrucoes.txt
#
#  Ao rodar, ele imprime no terminal uma LISTAGEM (endereco | binario | fonte)
#  para voce conferir, e grava so o binario no arquivo de saida.
#
#  SINTAXE DO ARQUIVO .asm
#  -----------------------
#    * Uma instrucao por linha.
#    * Comentario: tudo depois de ';' e ignorado.
#    * Rotulo (label): "nome:"  — sozinho na linha OU antes da instrucao.
#      Ele guarda o ENDERECO daquela instrucao; use em saltos e branches.
#    * Registradores: R0..R63.   Imediatos: decimal (12) ou hex (0xFA11).
#    * Linhas em branco sao ignoradas.
#
#  COMO ESCREVER CADA INSTRUCAO (as 37)
#  ------------------------------------
#    Aritm/logica reg : ADD|SUB|MUL|DIV|AND|OR|NOR|XNOR  rd, rs, rt   ; rd = rs OP rt
#    Aritm/logica imm : ADDI|SUBI|MULI|DIVI|ANDI|ORI     rd, rs, imm  ; rd = rs OP imm
#    Shift            : SL|SR                            rd, rs, imm  ; rd = rs <</>> imm
#    Move             : MOV  rd, rs        ; rd = rs
#                       MOVI rd, imm       ; rd = imm
#    Load             : LOADR rd, rs       ; rd = MEM[rs]
#                       LOADD rd, rs, imm  ; rd = MEM[rs+imm]
#                       LOADI rd, imm      ; rd = MEM[imm]
#    Store            : STORER rd, rs      ; MEM[rs]     = rd   (rd=dado, rs=endereco)
#                       STORED rd, rs, imm ; MEM[rs+imm] = rd
#                       STOREI rd, imm     ; MEM[imm]    = rd
#    Pilha            : PUSH rd            ; MEM[++RPI] = rd    (RPI = R63)
#                       POP  rd            ; rd = MEM[RPI--]
#    Branch           : BEQ|BNE|BLT|BGT  rs, rd, label
#                         compara reg[rs] com reg[rd]; se verdadeiro salta p/ label
#                         (BEQ: =,  BNE: !=,  BLT: rs<rd,  BGT: rs>rd)
#    Jump             : JMP label          ; PC = label
#                       JAL label          ; R62 = PC+1 ; PC = label   (chamada)
#                       JR  rd             ; PC = reg[rd]              (retorno: JR R62)
#    I/O              : IN  rd             ; rd = chaves (SW)
#                       OUT rs             ; display = reg[rs]
#    Sistema          : NOP                ; nao faz nada
#                       HLT                ; para o processador
#
#  CODIFICACAO (layout de 32 bits — igual ao Processador.v / Extensor.v)
#  --------------------------------------------------------------------
#    [31:26]=opcode  [25:20]=RD  [19:14]=RS  [13:8]=RT
#    [13:0]=END14 (imm curto)   [19:0]=END20 (MOVI/LOADI/STOREI)   [25:0]=END26 (JMP/JAL)
#    Branch: o campo gravado e o DESLOCAMENTO = label - (endereco_do_branch + 1),
#            porque o hardware faz PC = PC + 1 + deslocamento.
#
#  REGISTRADORES ESPECIAIS (convencao do hardware)
#  -----------------------------------------------
#    R0  = sempre 0        R61 = parte alta de MUL / resto de DIV
#    R62 = endereco de retorno (JAL grava, JR le)
#    R63 = ponteiro de pilha (RPI) usado por PUSH/POP
#    (MUL/DIV: a parte baixa/quociente vai para o RD que voce escolher; R61 = alta/resto)
# =============================================================================

use strict;
use warnings;

# ── Tabela de opcodes (de ucontrole.v) ───────────────────────────────────────
my %OP = (
  ADD=>0, ADDI=>1, SUB=>2, SUBI=>3, MUL=>4, MULI=>5, DIV=>6, DIVI=>7,
  AND=>8, ANDI=>9, OR=>10, ORI=>11, NOR=>12, XNOR=>13, SL=>14, SR=>15,
  MOV=>16, MOVI=>17, LOADR=>18, LOADD=>19, LOADI=>20, STORER=>21, STORED=>22, STOREI=>23,
  PUSH=>24, POP=>25, BEQ=>26, BNE=>27, BLT=>28, BGT=>29, JMP=>30, JAL=>31,
  JR=>32, IN=>33, OUT=>34, NOP=>35, HLT=>36,
);

# ── Argumentos ────────────────────────────────────────────────────────────────
my ($infile, $outfile) = @ARGV;
die "uso: perl asm.pl <entrada.asm> <saida.txt>\n" unless $infile && defined $outfile;
open(my $in, '<', $infile) or die "nao consegui abrir '$infile': $!\n";
my @raw = <$in>;
close $in;

# ── Passo 1: coletar labels (endereco de cada instrucao) e as instrucoes ─────
my (%label, @instr, @src);
my $addr = 0;
for my $line (@raw) {
    my $l = $line;
    $l =~ s/;.*//;             # remove comentario
    $l =~ s/^\s+|\s+$//g;      # tira espacos das pontas
    next if $l eq '';
    if ($l =~ /^(\w+):\s*(.*)$/) {   # ha um label nesta linha
        die "label repetido: $1\n" if exists $label{$1};
        $label{$1} = $addr;
        my $rest = $2;
        next if $rest eq '';         # label sozinho -> aponta p/ a proxima instrucao
        push @instr, $rest; push @src, $rest; $addr++;
    } else {
        push @instr, $l; push @src, $l; $addr++;
    }
}

sub reg {
    my $r = shift;
    $r =~ /^R(\d+)$/i or die "registrador invalido: '$r'\n";
    my $n = $1 + 0;
    die "registrador fora de R0..R63: $n\n" if $n > 63;
    return $n;
}
sub imm { my $v = shift; return ($v =~ /^0x/i) ? hex($v) : $v + 0; }

# ── Passo 2: montar cada instrucao em 32 bits ────────────────────────────────
my @bin;
for my $i (0 .. $#instr) {
    my @t = split /[\s,]+/, $instr[$i];
    my $m = uc(shift @t);
    die "opcode desconhecido na linha '$instr[$i]'\n" unless exists $OP{$m};
    my $w = $OP{$m} << 26;

    if    ($m =~ /^(ADD|SUB|MUL|DIV|AND|OR|NOR|XNOR)$/)              { $w |= (reg($t[0])<<20)|(reg($t[1])<<14)|(reg($t[2])<<8); }
    elsif ($m =~ /^(ADDI|SUBI|MULI|DIVI|ANDI|ORI|SL|SR|LOADD|STORED)$/) { $w |= (reg($t[0])<<20)|(reg($t[1])<<14)|(imm($t[2]) & 0x3FFF); }
    elsif ($m =~ /^(MOV|LOADR|STORER)$/)                            { $w |= (reg($t[0])<<20)|(reg($t[1])<<14); }
    elsif ($m =~ /^(MOVI|LOADI|STOREI)$/)                           { $w |= (reg($t[0])<<20)|(imm($t[1]) & 0xFFFFF); }
    elsif ($m =~ /^(PUSH|POP|JR|IN)$/)                              { $w |= (reg($t[0])<<20); }
    elsif ($m eq 'OUT')                                             { $w |= (reg($t[0])<<14); }
    elsif ($m =~ /^(BEQ|BNE|BLT|BGT)$/) {
        my ($rs,$rd) = (reg($t[0]), reg($t[1]));
        die "label ausente: '$t[2]'\n" unless exists $label{$t[2]};
        my $off = $label{$t[2]} - ($i + 1);                # PC = PC+1+off
        $w |= ($rd<<20)|($rs<<14)|($off & 0x3FFF);
    }
    elsif ($m =~ /^(JMP|JAL)$/) {
        die "label ausente: '$t[0]'\n" unless exists $label{$t[0]};
        $w |= ($label{$t[0]} & 0x3FFFFFF);
    }
    elsif ($m =~ /^(NOP|HLT)$/) { }                        # so opcode
    else { die "sem regra de codificacao para $m\n"; }

    push @bin, sprintf("%032b", $w);
    printf "%3d  %s  %s\n", $i, $bin[-1], $src[$i];        # listagem no terminal
}

# ── Grava o binario ──────────────────────────────────────────────────────────
open(my $out, '>', $outfile) or die "nao consegui gravar '$outfile': $!\n";
print $out "$_\n" for @bin;
close $out;
printf "\nOK: %d instrucoes -> %s\n", scalar(@bin), $outfile;
