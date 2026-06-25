;==============================================================================
; carrinho_2motores.asm  -  ATmega328P @ 16 MHz
;------------------------------------------------------------------------------
; Controle de 2 motores DC por 2 pontes-H externas (ex.: L298N / TB6612).
;   - 4 modos de movimento: FRENTE, RE, GIRO-DIREITA, GIRO-ESQUERDA (+ PARADO)
;   - 1 PWM unico (OC0A / PD6) alimenta os dois ENABLE -> mesma freq. e duty
;   - 3 modos de velocidade (lento / padrao / rapido) trocados por botao
;   - botoes lidos por amostragem dentro de uma interrupcao de timer, com
;     debounce e exigencia de "soltar antes de aceitar novo aperto"
;
; Toda a temporizacao roda em interrupcao; o loop principal so despacha eventos.
;
; OBS p/ avr_sim: o dispositivo (ATmega328P) e escolhido no projeto, entao os
;   nomes de registradores/bits/vetores ja sao conhecidos -> NAO use .include.
;   (Se montar com avra/avrasm2, adicione no topo:  .include "m328Pdef.inc")
;==============================================================================

.include "m328Pdef.inc"

;----------------------------- aliases de registrador -------------------------
.def temp = r16           ; temporario geral
.def raw  = r19           ; amostra bruta de PINC dentro da ISR

;----------------------------- mapa de pinos ----------------------------------
; Ponte-H ESQUERDA (Motor E)         Ponte-H DIREITA (Motor D)
;   PD2 = IN1 (E)                      PD4 = IN1 (D)
;   PD3 = IN2 (E)                      PD5 = IN2 (D)
; Convencao por roda: IN1=1,IN2=0 -> "frente"  |  IN1=0,IN2=1 -> "tras"
.equ LIN1 = PD2
.equ LIN2 = PD3
.equ RIN1 = PD4
.equ RIN2 = PD5

; PWM unico (saida OC0A do Timer0) -> ligar FISICAMENTE em ENA E ENB
.equ PWM_PIN = PD6

; Botoes (PORTC) com pull-up interno; pressionado = nivel BAIXO (vai ao GND)
.equ BTN_MODE  = PC0      ; cicla o modo de movimento
.equ BTN_SPEED = PC1      ; cicla a velocidade

;----------------------------- estados de movimento ---------------------------
.equ ST_STOP  = 0
.equ ST_FWD   = 1
.equ ST_BWD   = 2
.equ ST_RIGHT = 3
.equ ST_LEFT  = 4
.equ ST_MAX   = 4         ; ultimo estado valido (depois volta a ST_STOP)

;----------------------------- modos de velocidade ----------------------------
.equ SPD_SLOW = 0
.equ SPD_STD  = 1
.equ SPD_FAST = 2
.equ SPD_MAX  = 2

; duty cycle (0..255) de cada modo  -> AJUSTE conforme seu motor/ponte
.equ DUTY_SLOW = 90       ; ~35%
.equ DUTY_STD  = 160      ; ~63%
.equ DUTY_FAST = 255      ; 100%

;----------------------------- debounce ---------------------------------------
.equ DEBOUNCE_TICKS = 20  ; 20 amostras * 1 ms = 20 ms estaveis p/ validar

; bits do byte de eventos (evFlags)
.equ EV_MODE  = 0
.equ EV_SPEED = 1

;==============================================================================
;                              SEGMENTO DE CODIGO
;==============================================================================
.cseg
.org 0x0000
    rjmp RESET            ; vetor de RESET

.org 0x0016              ; vetor TIMER1_COMPA (OC1Aaddr)
    rjmp TIMER1_COMPA

.org 0x0034             ; primeira posicao livre apos a tabela de vetores
;------------------------------------------------------------------------------
RESET:
    ;--- pilha ---
    ldi temp, high(RAMEND)
    out SPH, temp
    ldi temp, low(RAMEND)
    out SPL, temp

    ;--- PORTD: PD2..PD6 saida; demais entrada. Tudo 0 = motores parados ---
    ldi temp, (1<<LIN1)|(1<<LIN2)|(1<<RIN1)|(1<<RIN2)|(1<<PWM_PIN)
    out DDRD, temp
    ldi temp, 0x00
    out PORTD, temp

    ;--- PORTC: PC0/PC1 entrada com pull-up ---
    cbi DDRC, BTN_MODE
    cbi DDRC, BTN_SPEED
    sbi PORTC, BTN_MODE
    sbi PORTC, BTN_SPEED

    ;--- Timer0: Fast PWM (modo 3, TOP=0xFF), saida OC0A nao-invertida ---
    ; COM0A1=1 -> OC0A nao-invertido ; WGM01=1,WGM00=1 -> Fast PWM
    ldi temp, (1<<COM0A1)|(1<<WGM01)|(1<<WGM00)
    out TCCR0A, temp
    ; CS01=1,CS00=1 -> prescaler /64  => f_pwm = 16MHz/(64*256) ~= 976 Hz
    ldi temp, (1<<CS01)|(1<<CS00)
    out TCCR0B, temp

    ;--- Timer1: CTC (modo 4), tick periodico de 1 ms p/ ler botoes ---
    ; TCCR1A fica 0 (reset). WGM12=1 em TCCR1B -> CTC com TOP=OCR1A.
    ; CS11=1,CS10=1 -> prescaler /64 ; OCR1A=249 -> (249+1)*64/16MHz = 1 ms.
    ldi temp, (1<<WGM12)|(1<<CS11)|(1<<CS10)
    sts TCCR1B, temp
    ldi temp, high(249)
    sts OCR1AH, temp                 ; escrever H ANTES de L (registrador de 16 bits)
    ldi temp, low(249)
    sts OCR1AL, temp
    ldi temp, (1<<OCIE1A)            ; habilita IRQ de compare match A
    sts TIMSK1, temp

    ;--- variaveis em SRAM ---
    ldi temp, ST_STOP
    sts motorState, temp
    ldi temp, SPD_STD
    sts speedMode, temp
    ldi temp, 1                      ; botoes "armados" (prontos p/ aceitar aperto)
    sts modeArmed, temp
    sts spdArmed, temp
    clr temp
    sts modeCnt, temp
    sts spdCnt, temp
    sts evFlags, temp

    ;--- condicao inicial: parado, velocidade padrao ---
    rcall apply_speed
    rcall fsm_apply

    sei                              ; habilita interrupcoes globais

;------------------------------------------------------------------------------
; LOOP PRINCIPAL: so despacha os eventos sinalizados pela ISR (mantem ISR curta)
;------------------------------------------------------------------------------
main_loop:
    lds  temp, evFlags
    sbrc temp, EV_MODE               ; aperto validado no botao de modo?
    rcall handle_mode_event
    lds  temp, evFlags
    sbrc temp, EV_SPEED              ; aperto validado no botao de velocidade?
    rcall handle_speed_event
    rjmp main_loop

;==============================================================================
; TRATADORES DE EVENTO (rodam fora da ISR)
;==============================================================================
handle_mode_event:
    lds  temp, motorState
    inc  temp                        ; proximo modo
    cpi  temp, ST_MAX+1
    brlo hme_ok                      ; ainda dentro da faixa valida?
    ldi  temp, ST_STOP               ; senao volta ao inicio (PARADO)
hme_ok:
    sts  motorState, temp
    rcall fsm_apply                  ; aplica nas saidas das pontes
    lds  temp, evFlags               ; limpa o flag do evento
    cbr  temp, (1<<EV_MODE)
    sts  evFlags, temp
    ret

handle_speed_event:
    lds  temp, speedMode
    inc  temp
    cpi  temp, SPD_MAX+1
    brlo hse_ok
    ldi  temp, SPD_SLOW
hse_ok:
    sts  speedMode, temp
    rcall apply_speed                ; atualiza o duty do PWM unico
    lds  temp, evFlags
    cbr  temp, (1<<EV_SPEED)
    sts  evFlags, temp
    ret

;==============================================================================
; FSM: aplica nas pontes-H a combinacao correspondente ao motorState
;==============================================================================
fsm_apply:
    lds  temp, motorState
    cpi  temp, ST_FWD
    breq move_forward
    cpi  temp, ST_BWD
    breq move_backward
    cpi  temp, ST_RIGHT
    breq turn_right
    cpi  temp, ST_LEFT
    breq turn_left
    rjmp motor_stop                  ; ST_STOP (default)

;--- FRENTE: as duas rodas "para frente" (carrinho avanca) --------------------
; Com motores espelhados, "ambas para frente" corresponde a rotacoes FISICAS
; opostas (uma roda horario, outra anti-horario) -> exatamente sua descricao.
move_forward:
    sbi PORTD, LIN1
    cbi PORTD, LIN2
    sbi PORTD, RIN1
    cbi PORTD, RIN2
    ret

;--- RE: as duas rodas "para tras" --------------------------------------------
move_backward:
    cbi PORTD, LIN1
    sbi PORTD, LIN2
    cbi PORTD, RIN1
    sbi PORTD, RIN2
    ret

;--- GIRO DIREITA (no proprio eixo): roda E p/ frente, roda D p/ tras ---------
; resultado: carrinho gira no sentido horario (visto de cima) = vira p/ direita
turn_right:
    sbi PORTD, LIN1
    cbi PORTD, LIN2
    cbi PORTD, RIN1
    sbi PORTD, RIN2
    ret

;--- GIRO ESQUERDA (no proprio eixo): roda E p/ tras, roda D p/ frente --------
turn_left:
    cbi PORTD, LIN1
    sbi PORTD, LIN2
    sbi PORTD, RIN1
    cbi PORTD, RIN2
    ret

;--- PARADO: desliga as 4 chaves (motores em roda-livre) ----------------------
motor_stop:
    cbi PORTD, LIN1
    cbi PORTD, LIN2
    cbi PORTD, RIN1
    cbi PORTD, RIN2
    ret

;==============================================================================
; apply_speed: carrega OCR0A com o duty do modo atual (tabela em flash via LPM)
;==============================================================================
apply_speed:
    ldi  ZL, low(speed_table << 1)   ; endereco de BYTE da tabela (LPM usa byte)
    ldi  ZH, high(speed_table << 1)
    lds  temp, speedMode
    add  ZL, temp                    ; soma o indice (0..2)
    ldi  temp, 0
    adc  ZH, temp                    ; propaga eventual carry p/ ZH
    lpm  temp, Z                     ; le o duty da flash
    out  OCR0A, temp                 ; aplica no PWM
    ret

; tabela de duty (4 bytes p/ alinhar em palavra; o 0 final e so padding)
speed_table:
    .db DUTY_SLOW, DUTY_STD, DUTY_FAST, 0

;==============================================================================
; ISR Timer1 COMPA  -  executa a cada 1 ms
;   - le PINC uma unica vez (amostra coerente dos dois botoes)
;   - debounce por contagem; gera evento apenas na borda de aperto validada
;   - exige soltar o botao (re-arma) antes de aceitar novo aperto
;==============================================================================
TIMER1_COMPA:
    push temp
    in   temp, SREG
    push temp                        ; salva SREG na pilha
    push raw

    in   raw, PINC                   ; leitura unica e coerente dos botoes

    ;------------------ BOTAO DE MODO (PC0) ------------------
    sbrs raw, BTN_MODE               ; bit=1 -> NAO pressionado -> pula o rjmp
    rjmp mode_pressed
    ; --- solto: zera contador e re-arma ---
    clr  temp
    sts  modeCnt, temp
    ldi  temp, 1
    sts  modeArmed, temp
    rjmp check_speed
mode_pressed:
    lds  temp, modeCnt
    cpi  temp, DEBOUNCE_TICKS
    brsh check_speed                 ; ja saturou (aguardando soltar) -> ignora
    inc  temp
    sts  modeCnt, temp
    cpi  temp, DEBOUNCE_TICKS
    brlo check_speed                 ; ainda nao estabilizou
    ; estabilizou agora: se armado, gera evento e desarma
    lds  temp, modeArmed
    tst  temp
    breq check_speed
    clr  temp
    sts  modeArmed, temp
    lds  temp, evFlags
    sbr  temp, (1<<EV_MODE)
    sts  evFlags, temp

    ;------------------ BOTAO DE VELOCIDADE (PC1) ------------------
check_speed:
    sbrs raw, BTN_SPEED
    rjmp spd_pressed
    clr  temp
    sts  spdCnt, temp
    ldi  temp, 1
    sts  spdArmed, temp
    rjmp isr_end
spd_pressed:
    lds  temp, spdCnt
    cpi  temp, DEBOUNCE_TICKS
    brsh isr_end
    inc  temp
    sts  spdCnt, temp
    cpi  temp, DEBOUNCE_TICKS
    brlo isr_end
    lds  temp, spdArmed
    tst  temp
    breq isr_end
    clr  temp
    sts  spdArmed, temp
    lds  temp, evFlags
    sbr  temp, (1<<EV_SPEED)
    sts  evFlags, temp

isr_end:
    pop  raw
    pop  temp                        ; recupera SREG -> temp
    out  SREG, temp
    pop  temp                        ; recupera temp original
    reti

;==============================================================================
;                          SEGMENTO DE DADOS (SRAM)
;==============================================================================
.dseg
.org SRAM_START                      ; 0x0100 no ATmega328P
motorState: .byte 1                  ; estado de movimento (0..4)
speedMode:  .byte 1                  ; modo de velocidade (0..2)
modeCnt:    .byte 1                  ; contador de debounce do botao de modo
modeArmed:  .byte 1                  ; 1 = pronto p/ aceitar novo aperto (modo)
spdCnt:     .byte 1                  ; contador de debounce do botao de velocidade
spdArmed:   .byte 1                  ; 1 = pronto p/ aceitar novo aperto (veloc.)
evFlags:    .byte 1                  ; bit0=EV_MODE, bit1=EV_SPEED'
