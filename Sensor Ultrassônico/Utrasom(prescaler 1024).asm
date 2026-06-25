; ============================================================
; PROJETO: CARRINHO AUTÔNOMO - HC-SR04 COM TIMER2
; MCU    : ATmega328P @ 16MHz
;
; LIGAÇÕES:
;   TRIG -> PD2
;   ECHO -> PD3
;   LED  -> PD4
;
; ============================================================

.include "m328Pdef.inc"

.def    TEMP1   = R16
.def    TEMP2   = R17
.def    DIST_CM = R20

.equ    TRIG = 2             ; PD2
.equ    ECHO = 3             ; PD3
.equ    LED  = 4             ; PD4
.equ    LIMIAR_CM = 10       ; 10cm

; ============================================================
; VARIÁVEIS NA SRAM
; ============================================================
.dseg
.org 0x0100
ESTADO_LED:     .byte 1      ; 0=apagado, 1=aceso

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
        sbi     DDRD, TRIG
        cbi     DDRD, ECHO
        sbi     DDRD, LED
        cbi     PORTD, TRIG
        cbi     PORTD, LED

        ; --- Inicializa variável ---
        clr     TEMP1
        sts     ESTADO_LED, TEMP1

        ; --- Timer2 em modo normal ---
        clr     TEMP1
        sts     TCCR2A, TEMP1
        sts     TCCR2B, TEMP1

; ============================================================
; LOOP PRINCIPAL
; ============================================================
LOOP_PRINCIPAL:
        rcall   DISPARA_TRIGGER
        rcall   ESPERA_ECHO_SUBIR
        brcs    SEM_ECO

        rcall   CRONOMETRA_ECHO
        rcall   CONVERTE_PARA_CM
        rjmp    AVALIA_DISTANCIA

SEM_ECO:
        ldi     DIST_CM, 255

AVALIA_DISTANCIA:
        rcall   ATUALIZA_LED

        ldi     TEMP1, 80
        rcall   ESPERA_MS

        rjmp    LOOP_PRINCIPAL

; ============================================================
; DISPARA_TRIGGER (10us)
; ============================================================
DISPARA_TRIGGER:
        sbi     PORTD, TRIG
        ldi     TEMP1, 56
PULSO_TRIG:
        nop
        nop
        dec     TEMP1
        brne    PULSO_TRIG
        cbi     PORTD, TRIG
        ret

; ============================================================
; ESPERA_ECHO_SUBIR (com timeout)
; ============================================================
ESPERA_ECHO_SUBIR:
        ldi     TEMP2, 0xFF          ; timeout
LACO_ESPERA_SUBIDA:
        sbic    PIND, ECHO
        rjmp    ECHO_SUBIU_OK
        dec     TEMP2
        brne    LACO_ESPERA_SUBIDA
        sec                          ; timeout
        ret

ECHO_SUBIU_OK:
        clc                          ; sucesso
        ret

; ============================================================
; CRONOMETRA_ECHO (USANDO TIMER2!)
; Timer2 com prescaler 1024 → 1 tick = 64µs
; Leitura: TCNT2 (8 bits, 0-255) → distância até ~110cm
; ============================================================
CRONOMETRA_ECHO:
        ; Zera Timer2
        clr     TEMP1
        sts     TCNT2, TEMP1

        ; Liga Timer2 com prescaler 1024 (CS22=1, CS21=1, CS20=1)
        ldi     TEMP1, (1<<CS22) | (1<<CS21) | (1<<CS20)
        sts     TCCR2B, TEMP1

        ; Timeout para não travar
        ldi     TEMP2, 0xFF

ESPERA_ECHO_DESCER:
        sbis    PIND, ECHO
        rjmp    ECHO_DESCEU_OK

        dec     TEMP2
        brne    ESPERA_ECHO_DESCER

        ; TIMEOUT
        clr     TEMP1
        sts     TCCR2B, TEMP1
        ldi     TEMP1, 0xFF
        mov     DIST_CM, TEMP1
        ret

ECHO_DESCEU_OK:
        ; Para o Timer2
        clr     TEMP1
        sts     TCCR2B, TEMP1

        ; Lê TCNT2 (8 bits, leitura simples!)
        lds     DIST_CM, TCNT2
        ret

; ============================================================
; CONVERTE_PARA_CM (SIMPLIFICADO!)
; DIST_CM ≈ TCNT2 (prescaler 1024)
; ============================================================
CONVERTE_PARA_CM:

        ret

; ============================================================
; ATUALIZA_LED (com histerese)
; ============================================================
ATUALIZA_LED:
        push    TEMP1
        lds     TEMP1, ESTADO_LED

        cpi     DIST_CM, LIMIAR_CM
        brsh    TESTA_LONGE

        ; Obstáculo detectado
        sbi     PORTD, LED
        ldi     TEMP1, 1
        sts     ESTADO_LED, TEMP1
        rjmp    FIM_LED

TESTA_LONGE:
        cpi     TEMP1, 1
        brne    LED_APAGADO

        ; Histerese: só apaga se DIST_CM > LIMIAR_CM + 2
        mov     TEMP1, DIST_CM
        subi    TEMP1, LIMIAR_CM
        cpi     TEMP1, 2
        brlo    FIM_LED

LED_APAGADO:
        cbi     PORTD, LED
        clr     TEMP1
        sts     ESTADO_LED, TEMP1

FIM_LED:
        pop     TEMP1
        ret

; ============================================================
; ESPERA_MS (delay em ms)
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
; FIM
; ============================================================
