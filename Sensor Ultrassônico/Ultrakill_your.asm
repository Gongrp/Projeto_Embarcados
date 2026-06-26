; ============================================================
; PROJETO: CARRINHO AUTÔNOMO - HC-SR04 COM TIMER2 (PRESCALER 256)
; MCU    : ATmega328P @ 16MHz
; VERSÃO CORRIGIDA
;
; LIGAÇÕES:
;   TRIG -> PD2 (pino digital 2)
;   ECHO -> PD3 (pino digital 3)
;   LED  -> PD4 (pino digital 4)
;
; CONFIGURAÇÃO DO TIMER2:
;   - Prescaler 256 (CS22=1, CS21=1, CS20=0)
;   - 1 tick = 16µs
;   - Fórmula: cm = (TCNT2 * 10) / 36
;   - Alcance máximo: ~70cm (limitado pelo overflow do Timer2
;     em 256 ticks = 4,096ms ≈ 70cm, usado como timeout natural)
;
; CORREÇÕES APLICADAS:
;   1. CONVERTE_PARA_CM agora usa multiplicação em 16 bits (mul)
;      em vez de 8 bits, evitando overflow silencioso.
;   2. Timeouts de ESPERA_ECHO_SUBIR e ESPERA_ECHO_DESCER agora
;      usam a flag TOV2 do próprio Timer2 (4,096ms) em vez de um
;      contador de poucas iterações (~64µs), que causava timeout
;      quase sempre.
;   3. Registrador TEMP3 (usado em ESPERA_MS) foi declarado.
; ============================================================

.include "m328Pdef.inc"

.def    TEMP1   = R16
.def    TEMP2   = R17
.def    TEMP3   = R18        ; CORRIGIDO: faltava esta declaração
.def    DIST_CM = R20

.equ    TRIG = 2             ; PD2
.equ    ECHO = 3             ; PD3
.equ    LED  = 4             ; PD4
.equ    LIMIAR_CM = 10       ; distância para detectar (cm)

; ============================================================
; VARIÁVEIS NA SRAM
; ============================================================
.dseg
.org 0x0100
ESTADO_LED:     .byte 1      ; 0=apagado, 1=aceso

; ============================================================
; VETOR DE RESET
; ============================================================
.cseg
.org    0x0000
        rjmp    INICIO

; ============================================================
; CONFIGURAÇÃO INICIAL
; ============================================================
INICIO:
        ; --- Pilha ---
        ldi     TEMP1, low(RAMEND)
        out     SPL, TEMP1
        ldi     TEMP1, high(RAMEND)
        out     SPH, TEMP1

        ; --- Pinos ---
        sbi     DDRD, TRIG          ; TRIG = saída
        cbi     DDRD, ECHO          ; ECHO = entrada
        sbi     DDRD, LED           ; LED = saída

        cbi     PORTD, TRIG         ; TRIG inicia em 0
        cbi     PORTD, LED          ; LED inicia apagado

        ; --- Inicializa variável ---
        clr     TEMP1
        sts     ESTADO_LED, TEMP1

        ; --- Timer2 em modo normal (prescaler desligado) ---
        clr     TEMP1
        sts     TCCR2A, TEMP1
        sts     TCCR2B, TEMP1

; ============================================================
; LOOP PRINCIPAL
; ============================================================
LOOP_PRINCIPAL:
        rcall   DISPARA_TRIGGER
        rcall   ESPERA_ECHO_SUBIR
        brcs    SEM_ECO              ; Carry=1 = timeout

        rcall   CRONOMETRA_ECHO
        rcall   CONVERTE_PARA_CM
        rjmp    AVALIA_DISTANCIA

SEM_ECO:
        ldi     DIST_CM, 0xFF        ; valor alto = "sem obstáculo"

AVALIA_DISTANCIA:
        rcall   ATUALIZA_LED

        ; Pausa entre medições (evita saturar o sensor)
        ldi     TEMP1, 80            ; 80ms
        rcall   ESPERA_MS

        rjmp    LOOP_PRINCIPAL

; ============================================================
; DISPARA_TRIGGER - Gera pulso de 10us no TRIG
; ============================================================
DISPARA_TRIGGER:
        sbi     PORTD, TRIG
        ldi     TEMP1, 50
PULSO_TRIG:
        nop
        nop
        dec     TEMP1
        brne    PULSO_TRIG
        cbi     PORTD, TRIG
        ret

; ============================================================
; ESPERA_ECHO_SUBIR - Aguarda ECHO = 1 (com timeout via Timer2)
; CORRIGIDO: usa o próprio Timer2 (overflow = 4,096ms) como
; referência de timeout, em vez de poucas iterações de loop
; (~64µs), que disparava falso timeout quase sempre.
; Retorna: Carry=1 se timeout, Carry=0 se sucesso
; ============================================================
ESPERA_ECHO_SUBIR:
        ; Zera o contador e a flag de overflow, e liga o Timer2
        clr     TEMP1
        sts     TCNT2, TEMP1
        ldi     TEMP1, (1<<TOV2)
        out     TIFR2, TEMP1         ; limpa flag pendente (escreve 1 para limpar)
        ldi     TEMP1, (1<<CS22) | (1<<CS21)
        sts     TCCR2B, TEMP1        ; inicia Timer2 com prescaler 256

LACO_ESPERA_SUBIDA:
        sbic    PIND, ECHO
        rjmp    ECHO_SUBIU_OK
        in      TEMP1, TIFR2
        sbrc    TEMP1, TOV2
        rjmp    TIMEOUT_SUBIDA
        rjmp    LACO_ESPERA_SUBIDA

TIMEOUT_SUBIDA:
        clr     TEMP1
        sts     TCCR2B, TEMP1        ; para o timer
        sec                          ; timeout
        ret

ECHO_SUBIU_OK:
        ; Não para o timer aqui: CRONOMETRA_ECHO vai reiniciá-lo
        clc                          ; sucesso
        ret

; ============================================================
; CRONOMETRA_ECHO - Mede o tempo que ECHO fica em 1
; Timer2 com prescaler 256: 1 tick = 16µs
; CORRIGIDO: timeout agora usa a flag TOV2 (overflow em 256
; ticks = 4,096ms ≈ 70cm), coerente com o alcance máximo do
; projeto, em vez de poucas iterações de loop.
; Resultado em DIST_CM (valor bruto em ticks, 0-255)
; ============================================================
CRONOMETRA_ECHO:
        ; Reinicia o Timer2 do zero a partir da borda de subida
        clr     TEMP1
        sts     TCCR2B, TEMP1        ; para o timer
        sts     TCNT2, TEMP1         ; zera o contador
        ldi     TEMP1, (1<<TOV2)
        out     TIFR2, TEMP1         ; limpa flag pendente
        ldi     TEMP1, (1<<CS22) | (1<<CS21)
        sts     TCCR2B, TEMP1        ; liga Timer2 com prescaler 256

ESPERA_ECHO_DESCER:
        sbis    PIND, ECHO          ; se ECHO=0, sai do loop
        rjmp    ECHO_DESCEU_OK
        in      TEMP1, TIFR2
        sbrc    TEMP1, TOV2
        rjmp    TIMEOUT_DESCIDA
        rjmp    ESPERA_ECHO_DESCER

TIMEOUT_DESCIDA:
        ; TIMEOUT: para o timer e retorna distância máxima
        clr     TEMP1
        sts     TCCR2B, TEMP1
        ldi     DIST_CM, 0xFF
        ret

ECHO_DESCEU_OK:
        ; Para o Timer2
        clr     TEMP1
        sts     TCCR2B, TEMP1

        ; Lê TCNT2 (8 bits, 0-255)
        lds     DIST_CM, TCNT2
        ret

; ============================================================
; CONVERTE_PARA_CM - Converte ticks para centímetros
; Fórmula: cm = (TCNT2 * 10) / 36
; CORRIGIDO: a multiplicação por 10 pode chegar a 2550, o que
; não cabe em 8 bits (estourava silenciosamente antes). Agora
; usa a instrução MUL (resultado 16 bits em R1:R0) e uma divisão
; por 36 também em 16 bits.
; ============================================================
CONVERTE_PARA_CM:
        push    TEMP1
        push    TEMP2
        push    TEMP3
        push    r0
        push    r1

        mov     TEMP2, DIST_CM      ; TEMP2 = ticks (0-255)
        ldi     TEMP1, 10
        mul     TEMP2, TEMP1        ; R1:R0 = ticks * 10 (até 2550, 16 bits)
        mov     TEMP1, r0           ; TEMP1 = byte baixo do produto
        mov     TEMP3, r1           ; TEMP3 = byte alto do produto

        ; Divide o valor de 16 bits (TEMP3:TEMP1) por 36
        ; por subtração repetida, contando em DIST_CM
        clr     DIST_CM
DIV_LOOP:
        tst     TEMP3
        brne    DIV_SUBTRAI         ; byte alto != 0 -> valor >= 256 >= 36
        cpi     TEMP1, 36
        brlo    DIV_FIM             ; byte alto = 0 e baixo < 36 -> terminou

DIV_SUBTRAI:
        subi    TEMP1, 36
        brcc    DIV_SEM_EMPRESTIMO
        dec     TEMP3               ; houve "borrow", ajusta byte alto
DIV_SEM_EMPRESTIMO:
        inc     DIST_CM
        rjmp    DIV_LOOP
DIV_FIM:

        pop     r1
        pop     r0
        pop     TEMP3
        pop     TEMP2
        pop     TEMP1
        ret

; ============================================================
; ATUALIZA_LED - Com histerese para evitar oscilação
; Acende se DIST_CM < LIMIAR_CM (10cm)
; Apaga se DIST_CM > LIMIAR_CM + 2 (12cm)
; ============================================================
ATUALIZA_LED:
        push    TEMP1
        lds     TEMP1, ESTADO_LED

        ; Se distância < limite, acende
        cpi     DIST_CM, LIMIAR_CM
        brsh    TESTA_LONGE

        ; OBSTÁCULO DETECTADO
        sbi     PORTD, LED
        ldi     TEMP1, 1
        sts     ESTADO_LED, TEMP1
        rjmp    FIM_LED

TESTA_LONGE:
        ; Se já estava apagado, mantém apagado
        cpi     TEMP1, 1
        brne    LED_APAGADO

        ; Estava aceso: só apaga se distância > LIMIAR_CM + 2
        mov     TEMP1, DIST_CM
        subi    TEMP1, LIMIAR_CM
        cpi     TEMP1, 2
        brlo    FIM_LED             ; ainda perto, mantém aceso

LED_APAGADO:
        cbi     PORTD, LED
        clr     TEMP1
        sts     ESTADO_LED, TEMP1

FIM_LED:
        pop     TEMP1
        ret

; ============================================================
; ESPERA_MS - Delay em milissegundos (aproximado)
; Entrada: TEMP1 = número de ms (0-255)
; ============================================================
ESPERA_MS:
        push    TEMP1
        push    TEMP2
        push    TEMP3
LOOP_MS:
        ldi     TEMP2, 4
LOOP_4:
        ldi     TEMP3, 250
LOOP_250:
        dec     TEMP3
        brne    LOOP_250
        dec     TEMP2
        brne    LOOP_4
        dec     TEMP1
        brne    LOOP_MS
        pop     TEMP3
        pop     TEMP2
        pop     TEMP1
        ret

; ============================================================
; FIM DO PROGRAMA
; ============================================================
