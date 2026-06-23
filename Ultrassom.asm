; ============================================================
; PROJETO: CARRINHO AUTÔNOMO - SENSOR ULTRASSÔNICO HC-SR04
; MCU    : ATmega328P @ 16MHz
; Autor  : Implementação independente, baseada no datasheet
;
; LIGAÇÕES:
;   TRIG -> PD2 (pino digital 2 no Arduino)
;   ECHO -> PD3 (pino digital 3 no Arduino)
;   LED  -> PD4 (pino digital 4 no Arduino)
;
; PRINCÍPIO DE FUNCIONAMENTO (datasheet HC-SR04):
;   - Pulso HIGH >= 10us no TRIG dispara a medição
;   - Sensor emite burst ultrassônico de 40kHz
;   - ECHO fica HIGH durante o tempo de ida-e-volta do som
;   - Distância (cm) = tempo_em_us / 58
;
; OBJETIVO:
;   Medir distância continuamente. Se distância < 5cm,
;   acende LED (sinal para o carrinho fazer curva).
; ============================================================

.include "m328Pdef.inc"

.def    TEMP1   = R16
.def    TEMP2   = R17
.def    TEMP3   = R18
.def    DIST_CM = R20       ; resultado final da medição

.equ    PORTA_SENSOR = PORTD
.equ    DDR_SENSOR   = DDRD
.equ    PIN_SENSOR   = PIND

.equ    TRIG = 2             ; PD2
.equ    ECHO = 3             ; PD3
.equ    LED  = 4             ; PD4

.equ    LIMIAR_CM = 10        ; distância de detecção em cm

; ============================================================
; TABELA DE VETORES
; ============================================================
.cseg
.org    0x0000
        rjmp    INICIO

; ============================================================
; INÍCIO DO PROGRAMA
; ============================================================
INICIO:
        ; --- Pilha ---
        ldi     TEMP1, low(RAMEND)
        out     SPL, TEMP1
        ldi     TEMP1, high(RAMEND)
        out     SPH, TEMP1

        ; --- Direção dos pinos ---
        sbi     DDR_SENSOR, TRIG    ; TRIG = saída
        cbi     DDR_SENSOR, ECHO    ; ECHO = entrada
        sbi     DDR_SENSOR, LED     ; LED  = saída

        ; --- Estado inicial ---
        cbi     PORTA_SENSOR, TRIG
        cbi     PORTA_SENSOR, LED

        ; --- Timer1 em modo normal, sem prescaler ainda ---
        clr     TEMP1
        sts     TCCR1A, TEMP1
        sts     TCCR1B, TEMP1

; ============================================================
; LAÇO PRINCIPAL
; ============================================================
LOOP_PRINCIPAL:
        rcall   DISPARA_TRIGGER
        rcall   ESPERA_ECHO_SUBIR
        brcs    SEM_ECO              ; carry=1 -> sensor não respondeu

        rcall   CRONOMETRA_ECHO
        rcall   CONVERTE_PARA_CM
        rjmp    AVALIA_DISTANCIA

SEM_ECO:
        ldi     DIST_CM, 255         ; valor alto = "livre"

AVALIA_DISTANCIA:
        rcall   ATUALIZA_LED

        ; pausa entre medições (~80ms, recomendado pelo datasheet)
        ldi     TEMP1, 80
        rcall   ESPERA_MS

        rjmp    LOOP_PRINCIPAL

; ============================================================
; SUB-ROTINA: DISPARA_TRIGGER
; Gera pulso de 10us no pino TRIG
; ============================================================
DISPARA_TRIGGER:
        sbi     PORTA_SENSOR, TRIG
        ; 10us a 16MHz = 160 ciclos de clock
        ldi     TEMP1, 50
PULSO_TRIG: ;Aguarda 10 microsseg com TRIG em HIGH (implementado com decremento)
        nop
        nop
        dec     TEMP1
        brne    PULSO_TRIG
        cbi     PORTA_SENSOR, TRIG
        ret

; ============================================================
; SUB-ROTINA: ESPERA_ECHO_SUBIR
; Aguarda o pino ECHO ir para nível alto.
; Retorna: Carry = 1 se houve timeout (sem resposta do sensor)
;          Carry = 0 se ECHO subiu normalmente
; ============================================================
ESPERA_ECHO_SUBIR:
        push    TEMP2
        ldi     TEMP2, 0            ; contador de timeout (256 voltas)
LACO_ESPERA_SUBIDA:
        sbic    PIN_SENSOR, ECHO    ; se ECHO=0, pula a próxima linha
        rjmp    ECHO_OK_SUBIU
        dec     TEMP2
        brne    LACO_ESPERA_SUBIDA
        ; esgotou o tempo
        pop     TEMP2
        sec                         ; seta carry = timeout
        ret

ECHO_OK_SUBIU:
        pop     TEMP2
        clc                         ; limpa carry = sucesso
        ret

; ============================================================
; SUB-ROTINA: CRONOMETRA_ECHO
; Usa Timer1 (16 bits) com prescaler de 8 para contar
; quanto tempo o pino ECHO permanece em nível alto.
;
; Prescaler 8 @ 16MHz -> 1 tick = 0.5us
; Resultado fica em TEMP1:TEMP2 (não usado depois, pois
; convertemos direto pegando só os 8 bits baixos, que já
; cobrem distâncias de até ~25cm, suficiente para detecção
; de obstáculo próximo)
; ============================================================
CRONOMETRA_ECHO:
        ; zera Timer1
        clr     TEMP1
        sts    TCNT1H, TEMP1
        sts     TCNT1L, TEMP1

        ; liga Timer1 com prescaler 8 (CS12=0 CS11=1 CS10=0)
        ldi     TEMP1, (1<<CS11)
        sts    TCCR1B, TEMP1

ESPERA_ECHO_DESCER:
        sbis    PIN_SENSOR, ECHO    ; se ECHO=1, pula a próxima
        rjmp    ECHO_OK_DESCEU
        rjmp    ESPERA_ECHO_DESCER
        ;Inserir timeout para descida do ECHO

ECHO_OK_DESCEU:
        ; para o Timer1
        clr     TEMP1
        sts     TCCR1B, TEMP1

        ; lê resultado (usamos só byte baixo, suficiente p/ curto alcance) REVER QUAL O ALCANCE
        lds      TEMP3, TCNT1L
        ret

; ============================================================
; SUB-ROTINA: CONVERTE_PARA_CM
; Entrada: TEMP3 = contagem do Timer1 (1 tick = 0.5us)
; Saída  : DIST_CM = distância em centímetros
;
; Fórmula real:     cm = tempo_us / 58 VERIFICAR DE ONDE VEM O VALOR 58
; Como tempo_us = TEMP3 * 0.5, então:
;     cm = (TEMP3 * 0.5) / 58 = TEMP3 / 116
;
; Implementado por subtração repetida (divisão por 116)
; ============================================================
CONVERTE_PARA_CM:
        clr     DIST_CM
DIV_LOOP:
        cpi     TEMP3, 116
        brlo    DIV_FIM
        subi    TEMP3, 116
        inc     DIST_CM
        rjmp    DIV_LOOP
DIV_FIM:
        ret

; ============================================================
; SUB-ROTINA: ATUALIZA_LED
; Entrada: DIST_CM
; Acende LED se DIST_CM < LIMIAR_CM (obstáculo próximo)
; ============================================================
ATUALIZA_LED:
        cpi     DIST_CM, LIMIAR_CM
        brsh    LONGE
        sbi     PORTA_SENSOR, LED   ; obstáculo detectado
        ret
LONGE:
        cbi     PORTA_SENSOR, LED   ; caminho livre
        ret

; ============================================================
; SUB-ROTINA: ESPERA_MS
; Entrada: TEMP1 = número de milissegundos
; Delay aproximado calibrado para 16MHz
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
; ============================================================;
