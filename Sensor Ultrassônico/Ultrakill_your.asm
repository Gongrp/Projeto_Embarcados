; ============================================================
; PROJETO: HC-SR04 COM TIMER2 (PRESCALER 256) - VERSÃO TESTE
; MCU    : ATmega328P @ 16MHz
;
; LIGAÇÕES:
;   TRIG -> PD2
;   ECHO -> PD3
;   LED  -> PD4
; ============================================================

.include "m328Pdef.inc"

; ============================================================
.cseg
.org    0x0000
        rjmp    INICIO

; ============================================================
INICIO:
        ; Pilha
        ldi     R16, low(RAMEND)
        out     SPL, R16
        ldi     R16, high(RAMEND)
        out     SPH, R16

        ; Pinos
        sbi     DDRD, 2          ; TRIG (PD2) como saída
        cbi     DDRD, 3          ; ECHO (PD3) como entrada
        sbi     DDRD, 4          ; LED (PD4) como saída

        cbi     PORTD, 2         ; TRIG = 0
        cbi     PORTD, 4         ; LED = 0

        ; Timer2 parado
        clr     R16
        sts     TCCR2A, R16
        sts     TCCR2B, R16

; ============================================================
LOOP_PRINCIPAL:
        ; --- DISPARA TRIGGER (10us) ---
        sbi     PORTD, 2         ; TRIG = 1
        ldi     R16, 50
PULSO_TRIG:
        nop
        nop
        dec     R16
        brne    PULSO_TRIG
        cbi     PORTD, 2         ; TRIG = 0

        ; --- ESPERA ECHO SUBIR (com timeout) ---
        ldi     R17, 0xFF
ESPERA_SUBIDA:
        sbic    PIND, 3          ; se ECHO=1, pula
        rjmp    ECHO_SUBIU
        dec     R17
        brne    ESPERA_SUBIDA
        rjmp    SEM_OBSTACULO    ; timeout

ECHO_SUBIU:
        ; --- ZERA TIMER2 ---
        clr     R16
        sts     TCNT2, R16

        ; --- LIGA TIMER2 COM PRESCALER 256 ---
        ; CS22=1, CS21=1, CS20=0
        ldi     R16, (1<<CS22) | (1<<CS21)
        sts     TCCR2B, R16

        ; --- ESPERA ECHO DESCER (com timeout) ---
        ldi     R17, 0xFF
ESPERA_DESCIDA:
        sbis    PIND, 3          ; se ECHO=0, pula
        rjmp    ECHO_DESCEU
        dec     R17
        brne    ESPERA_DESCIDA

        ; --- TIMEOUT NA DESCIDA ---
        clr     R16
        sts     TCCR2B, R16
        rjmp    SEM_OBSTACULO

ECHO_DESCEU:
        ; --- PARA O TIMER2 ---
        clr     R16
        sts     TCCR2B, R16

        ; --- LÊ TCNT2 (valor bruto em ticks) ---
        lds     R16, TCNT2       ; R16 = ticks (0-255)

        ; --- CONVERTE PARA CM: cm = (ticks * 10) / 36 ---
        ; R16 = ticks
        mov     R17, R16         ; R17 = ticks
        lsl     R17              ; *2
        mov     R18, R17         ; R18 = *2
        lsl     R17              ; *4
        lsl     R17              ; *8
        add     R17, R18         ; *8 + *2 = *10
        ; R17 = ticks * 10 (0-2550)

        ; Divisão por 36 (subtração repetida)
        clr     R18              ; R18 = contador (cm)
DIV_LOOP:
        cpi     R17, 36
        brlo    DIV_FIM
        subi    R17, 36
        inc     R18
        rjmp    DIV_LOOP
DIV_FIM:
        ; R18 = distância em cm

        ; --- COMPARA COM LIMIAR (10cm) ---
        cpi     R18, 10
        brsh    SEM_OBSTACULO

        ; --- OBSTÁCULO DETECTADO (< 10cm) ---
        sbi     PORTD, 4         ; acende LED
        rjmp    FIM_CICLO

SEM_OBSTACULO:
        cbi     PORTD, 4         ; apaga LED

FIM_CICLO:
        ; --- DELAY ENTRE MEDIÇÕES (80ms) ---
        ldi     R16, 80
        rcall   DELAY_MS

        rjmp    LOOP_PRINCIPAL

; ============================================================
; DELAY_MS - Delay aproximado em milissegundos
; Entrada: R16 = número de ms
; ============================================================
DELAY_MS:
        push    R16
        push    R17
        push    R18
LOOP_MS:
        ldi     R17, 4
LOOP_4:
        ldi     R18, 250
LOOP_250:
        dec     R18
        brne    LOOP_250
        dec     R17
        brne    LOOP_4
        dec     R16
        brne    LOOP_MS
        pop     R18
        pop     R17
        pop     R16
        ret

; ============================================================
