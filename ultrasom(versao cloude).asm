; ============================================================
; MÓDULO: LEITURA DO HC-SR04 - DETECÇÃO DE OBSTÁCULO A 5cm
; MCU   : ATmega328P @ 16MHz
; Portas: TRIG = PB0 | ECHO = PB1 | LED  = PB5
;
; COMO FUNCIONA (datasheet HC-SR04):
;   1. Envia pulso HIGH de 10µs no pino TRIG
;   2. Sensor emite 8 pulsos ultrassônicos a 40kHz
;   3. Pino ECHO fica HIGH pelo tempo proporcional à distância
;   4. Distância (cm) = largura do pulso ECHO (µs) / 58
;
; SAÍDA:
;   - R16 = distância medida em centímetros
;   - LED aceso  → obstáculo detectado (distância < 5 cm)
;   - LED apagado → livre
; ============================================================

.include "m328Pdef.inc"

; ===== CONSTANTES =====
.equ    TRIG_PIN    = 0         ; PB0 - saída para o sensor
.equ    ECHO_PIN    = 1         ; PB1 - entrada do sensor
.equ    LED_PIN     = 5         ; PB5 - LED indicador (Arduino: pino 13)
.equ    DIST_LIMITE = 5         ; limiar de detecção em centímetros

; ============================================================
; VETOR DE RESET
; ============================================================
.cseg
.org 0x0000
    rjmp    RESET_vect

; ============================================================
; INICIALIZAÇÃO
; ============================================================
RESET_vect:
    ; Configura Stack Pointer
    ldi     R16, low(RAMEND)
    out     SPL, R16
    ldi     R16, high(RAMEND)
    out     SPH, R16

    rcall   config_pinos
    rcall   config_timer0

    sei                         ; habilita interrupções globais

; ============================================================
; LOOP PRINCIPAL
; ============================================================
main:
    rcall   medir_distancia     ; resultado em R16 (centímetros)
    rcall   verificar_obstaculo ; acende/apaga LED conforme R16

    ; Aguarda 100ms antes da próxima medição
    ; (datasheet recomenda ciclo mínimo de 60ms entre medições)
    ldi     R16, 100
    rcall   delay_ms

    rjmp    main

; ============================================================
; CONFIGURAÇÃO DOS PINOS
; ============================================================
config_pinos:
    sbi     DDRB, TRIG_PIN      ; TRIG → saída
    cbi     PORTB, TRIG_PIN     ; TRIG inicia em LOW

    cbi     DDRB, ECHO_PIN      ; ECHO → entrada (sem pull-up)

    sbi     DDRB, LED_PIN       ; LED  → saída
    cbi     PORTB, LED_PIN      ; LED  inicia apagado

    ret

; ============================================================
; CONFIGURAÇÃO DO TIMER0
; Prescaler 8 → cada tick = 0,5µs a 16MHz
; Assim 1 contagem = 0,5µs
; Para 5cm: tempo de ida e volta ≈ 5 * 58 = 290µs → 580 ticks
; Como Timer0 é 8 bits (0-255), usamos prescaler 64:
;   cada tick = 4µs
;   Para 5cm: 290µs / 4µs ≈ 73 contagens  ← cabe em 8 bits
;   Para 400cm (máximo): 23200µs / 4µs = 5800 → overflow tratado
; ============================================================
config_timer0:
    ldi     R16, 0x00
    out     TCCR0A, R16         ; modo normal
    ; Prescaler 64: CS01=1, CS00=1
    ldi     R16, (1<<CS01)|(1<<CS00)
    out     TCCR0B, R16
    ret

; ============================================================
; MEDIR DISTÂNCIA
; Saída: R16 = distância em centímetros (255 = sem obstáculo)
;
; Cálculo:
;   - Timer0 com prescaler 64 → 1 tick = 4µs
;   - Distância (cm) = (ticks * 4µs) / 58
;   - Simplificado:  distância ≈ ticks / 14,5 ≈ ticks / 15
;     (erro < 3% — suficiente para detecção de obstáculo)
; ============================================================
medir_distancia:
    push    R17
    push    R18

    ; --------------------------------------------------
    ; PASSO 1: Pulso de TRIGGER (mínimo 10µs)
    ; --------------------------------------------------
    sbi     PORTB, TRIG_PIN         ; TRIG = HIGH
    ldi     R18, 53                 ; ~13 ciclos por iteração
trig_delay:                         ; 53 × 3 ciclos = 159 ciclos
    dec     R18                     ; ≈ 10µs @ 16MHz
    brne    trig_delay
    cbi     PORTB, TRIG_PIN         ; TRIG = LOW

    ; --------------------------------------------------
    ; PASSO 2: Aguarda ECHO subir para HIGH
    ;          Timeout: ~255 iterações (~200µs)
    ; --------------------------------------------------
    ldi     R17, 0xFF
wait_echo_high:
    sbic    PINB, ECHO_PIN          ; pula se ECHO ainda = LOW
    rjmp    echo_subiu              ; ECHO = HIGH → começa contagem
    dec     R17
    brne    wait_echo_high
    ; Timeout: sensor não respondeu
    ldi     R16, 255
    rjmp    fim_medicao

echo_subiu:
    ; --------------------------------------------------
    ; PASSO 3: Zera Timer0 e aguarda ECHO descer para LOW
    ; --------------------------------------------------
    ldi     R16, 0
    out     TCNT0, R16              ; zera contador

wait_echo_low:
    sbis    PINB, ECHO_PIN          ; pula se ECHO ainda = HIGH
    rjmp    echo_desceu             ; ECHO = LOW → pulso terminou
    in      R18, TCNT0
    cpi     R18, 250                ; overflow check (250 ticks × 4µs = 1ms)
    brlo    wait_echo_low           ; ainda dentro do range
    ; Timeout: objeto muito longe (> ~40cm com este prescaler)
    ldi     R16, 255
    rjmp    fim_medicao

echo_desceu:
    ; --------------------------------------------------
    ; PASSO 4: Lê o timer e converte para centímetros
    ; --------------------------------------------------
    in      R16, TCNT0              ; R16 = contagens (1 count = 4µs)

    ; Divisão por 15 (aproxima / 58 com fator de 4µs)
    ; Resultado em R17 = distância em cm
    clr     R17
div_loop:
    cpi     R16, 15
    brlo    div_pronto
    subi    R16, 15
    inc     R17
    rjmp    div_loop

div_pronto:
    mov     R16, R17                ; R16 = distância em cm

fim_medicao:
    pop     R18
    pop     R17
    ret

; ============================================================
; VERIFICAR OBSTÁCULO E SINALIZAR COM LED
; Entrada: R16 = distância medida em centímetros
;
; LED aceso  → distância < DIST_LIMITE (5 cm)
; LED apagado → distância >= DIST_LIMITE
; ============================================================
verificar_obstaculo:
    cpi     R16, DIST_LIMITE
    brsh    apaga_led               ; >= 5cm: sem obstáculo

    ; Obstáculo detectado (< 5cm)
    sbi     PORTB, LED_PIN          ; acende LED
    ret

apaga_led:
    cbi     PORTB, LED_PIN          ; apaga LED
    ret

; ============================================================
; DELAY EM MILISSEGUNDOS
; Entrada: R16 = quantidade de milissegundos
; Usa R16, R17, R18 (preservados via push/pop)
; Calibrado para 16MHz
; ============================================================
delay_ms:
    push    R16
    push    R17
    push    R18

ms_loop:
    ldi     R17, 4              ; 4 laços externos por ms
outer_loop:
    ldi     R18, 250            ; 250 × 4 ciclos = 1000 ciclos = ~250µs
inner_loop:
    dec     R18
    brne    inner_loop
    dec     R17
    brne    outer_loop
    dec     R16
    brne    ms_loop

    pop     R18
    pop     R17
    pop     R16
    ret

; ============================================================
; FIM DO MÓDULO HC-SR04
; ============================================================
