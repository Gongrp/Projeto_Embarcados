;Código Completo - Controle de robozinho motorizado -  ATmega328P @ 16 MHz

;FUNCIONAMENTO:
;OBS.: (Incluir descrição)

.include "m328Pdef.inc"

;///////////////// CONSTANTES E PINAGEM ///////////////////////

;PODEMOS REDEFINIR OS PARÂMETROS AQUI FACILMENTE, SEM MEXER NO CORPO DO CÓDIGO (DE OLHO EM VCS FIR E MESTRE)


;PINOS

; Ponte-H ESQUERDA (Motor E)         Ponte-H DIREITA (Motor D)
;   PD2 = IN1 (E)                      PD4 = IN1 (D)
;   PD3 = IN2 (E)                      PD5 = IN2 (D)

; Convencao por roda: IN1=1,IN2=0 -> "frente"  |  IN1=0,IN2=1 -> "tras"

.equ LIN1 = PD2
.equ LIN2 = PD3
.equ RIN1 = PD4
.equ RIN2 = PD5
.equ PWM_PIN = PD6 ; PWM VELOCIDADE (saida OC0A do Timer0) -> ligar FISICAMENTE em ENA E ENB

; SENSOR ULTRASSÔNICO

.equ TRIG = PB4
.equ ECHO = PB3

;COMUNICAÇÃO USART MÓDULO BLUETOOTH

.equ RX = PD0
.equ TX = PD1


; CONSTANTES

;MODOS DE VELOCIDADE DO MOTOR

.equ DUTY_SLOW = 90       ; ~35%
.equ DUTY_STD  = 160      ; ~63%
.equ DUTY_FAST = 255      ; 100%

;Delay de rotação dos motores  (400ms)
.equ ROT_DELAY = 6250 		;Número de contagens com PS de 1024 -> N = T_DELAY(s) * (16M/PS)


;Baud rate comunicação USART:

;Distância de alcance sensor
.equ    LIMIAR_CM = 10

;Variável de controle de mudanças de direção realizadas (incrementada a cada rotação sucessiva e é zerado quando o carro pode seguir em frente)
.def ROT_COUNT = r22

;Variável de registro de ocorrência de interrupção do comparadorA
.def TIMER1_FLAG = r21


;////////////// VETORES DE INTERRUPÇÃO ///////////////////////////////

.cseg
.org 0x0000
rjmp config ;Pula para a SR de configuração

;Incluir interrupções para os timers 0 e 2?

.org 0x0016
rjmp INT_TIMER1_COMPA

.org 0x0024
rjmp INT_RX_USART


;////////////// CONFIGURAÇÕES INICIAIS //////////////////////////

.org 0x0034
config:

;Inicializando SP
ldi     R16,LOW(RAMEND)
out     SPL,R16
ldi     R16,HIGH(RAMEND)
out     SPH,R16

;Configurações iniciais de registradores

;Constante de comparação para sinalizar ativação de interrupts
ldi r16, 0x01
mov r12, r16

clr ROT_COUNT ;Inicia a contagem de rotações em zero


;Configuração das portas

;PORTD:
ldi r16, (1<<LIN1)|(1<<LIN2)|(1<<RIN1)|(1<<RIN2)|(1<<PWM_PIN)
out DDRD, r16
clr r16
out PORTD, r16
;Define todos os pinos dos motores como saída, zera os valores nas portas

;PORTB:
ldi r16, (1<<TRIG)
out DDRB,r16
clr r16
out PORTB,r16
;Define o pino do TRIG como saída e o do ECHO como entrada, zera os valores nas portas

;Configuração dos timers

;TIMER0 -> PWM velocidade dos motores

ldi r16, (1<<COM0A1)|(1<<WGM01)|(1<<WGM00)
out TCCR0A,r16                              ;Configura timer0 no modo fast pwm, conecta comparador A no modo não inversor
ldi r16, (1<<CS01)|(1<<CS00)
out TCCR0B,r16				    ;Configura PS 64
;Velocidade inicial??


;TIMER1 -> Delay de rotação do motor

;ldi r16, (1<<COM1A1)|(1<<WGM11)
clr r16
sts TCCR1A,r16                  ;Configura timer 1 no modo CTC conectando comparador A no modo não inversor
ldi r16, (1<<WGM12)
sts TCCR1B,r16			            ;Timer inicia desativado
ldi r16, low(ROT_DELAY)
sts OCR1AL,r16
ldi r16, high(ROT_DELAY)
sts OCR1AH,r16			;Salva no comparador o número de contagens definido pelo delay desejado -> Determina ângulo de rotação


;TIMER2 -> Detecção do sensor ultrassônico (tempo entre emissão no TRIG e recepção no ECHO)

ldi r16,0x00
sts TCCR2A,r16 	   ;Configura timer 2 no modo normal (delay)
sts TCCR2B,r16     ;Timer2 inicia desativado

;Configuração das interrupções:

;Interrupt do timer 1
ldi r16, (1<<OCIE1A)
sts TIMSK1,r16

;OBS. configurar demais interrupções

sei
;

;Configuração da comunicação USART


;OBS. preencher depois

;Inicialização dos motores em velocidade padrão

ldi r16, DUTY_STD
out OCR0A,r16		;Define duty cycle inicial dos motores

rcall RUN_MOTORS	;Inicia movimento para frente


;////////////////// CÓDIGO PRINCIPAL ///////////////////////////////

;loop principal -> Realiza o processo de medição com o sensor ultrassônico e determina se o carrinho deve mudar de direção

main:

;OBS.: INCORPORAR DEPOIS FILTRO MÉDIA MÓVEL PARA AS MEDIDAS DO ULTRASSONICO
rcall   DISPARA_TRIGGER
rcall   ESPERA_ECHO_SUBIR
brcs    SEM_ECO              ; carry=1 -> sensor não respondeu

rcall   CRONOMETRA_ECHO
rcall   CONVERTE_PARA_CM
rcall   AVALIA_DISTANCIA
rjmp 	COOLDOWN

SEM_ECO:
ldi     r20, 0xFF        ; valor alto = "livre"
rcall AVALIA_DISTANCIA

COOLDOWN:
; pausa entre medições (~80ms, recomendado pelo datasheet)
ldi     r16, 80
rcall   ESPERA_MS

rjmp   main; Reinicia loop principal



;////////////////////// SUB-ROTINAS //////////////////////////////////

DISPARA_TRIGGER:
sbi     PORTB, TRIG
;10us a 16MHz = 160 ciclos de clock
ldi     r17, 50

PULSO_TRIG: ;Aguarda 10 microsseg com TRIG em HIGH (implementado com decremento)
nop
nop
dec     r17
brne    PULSO_TRIG
cbi     PORTB, TRIG
ret


; Aguarda o pino ECHO ir para nível alto.
; Retorna: Carry = 1 se houve timeout (sem resposta do sensor)
;          Carry = 0 se ECHO subiu normalmente

ESPERA_ECHO_SUBIR:
clr r18           ; contador de timeout (256 voltas)
sts TCNT2,r18
ldi r18,(1<<TOV2)
out TIFR2,r18      ; limpa flag pendente (escreve 1 para limpar)
ldi r18, (1<<CS22)|(1<CS21)
sts TCCR2B,r18      ; inicia Timer2 com prescaler 256

LACO_ESPERA_SUBIDA:
sbic    PINB, ECHO    ; se ECHO=0, pula a próxima linha
rjmp    ECHO_OK_SUBIU
in      r18,TIFR2
sbrc    R18,TOV2
rjmp    TIMEOUT_SUBIDA
brne    LACO_ESPERA_SUBIDA

TIMEOUT_SUBIDA:
clr     r18
sts     TCCR2B, r18       ; para o timer
sec                          ; timeout
ret

ECHO_OK_SUBIU:
clc                         ; limpa carry = sucesso
ret

; Usa Timer2 com PS de 256 para contar quanto tempo o pino ECHO permanece em nível alto.

;/////// CRONOMETRA_ECHO /////////////////////

CRONOMETRA_ECHO:
clr     r16
sts     TCCR2B,r16 ;para o timer
sts     TCNT2, r16 ;zera o contador
ldi     r16, (1<<TOV2)
out     TIFR2, r16         ; limpa flag pendente

; Liga Timer2 com prescaler 256
ldi     r16, (1<<CS22) | (1<<CS21)
sts     TCCR2B, r16


ESPERA_ECHO_DESCER:
sbis    PINB, ECHO
rjmp    ECHO_DESCEU_OK
in      r16, TIFR2
sbrc    r16, TOV2
rjmp    TIMEOUT_DESCIDA
rjmp    ESPERA_ECHO_DESCER

TIMEOUT_DESCIDA:
; TIMEOUT: para o timer e retorna distância máxima
clr     r16
sts     TCCR2B,r16
ldi     r20,0xFF
ret


ECHO_DESCEU_OK:
clr     r16
sts     TCCR2B, r16 ;Para o timer2

lds     r20, TCNT2    ;Valor de tempo de demora da detecção será depois convertido em cm
ret

;//////////////////CONVERSÃO PARA CM ///////////////////////////////

CONVERTE_PARA_CM:
        push    R16
        push    R17
        push    R18
        push    r0
        push    r1

        mov     r17, r20      ; r17 = ticks (0-255)
        ldi     r16, 10
        mul     r17, r16        ; R1:R0 = ticks * 10 (até 2550, 16 bits)
        mov     r16, r0           ; r16 = byte baixo do produto
        mov     r18, r1           ; r18 = byte alto do produto

        ; Divide o valor de 16 bits (r18:r16) por 36
        ; por subtração repetida, contando em r20
        clr     r20
DIV_LOOP:
        tst     r18
        brne    DIV_SUBTRAI         ; byte alto != 0 -> valor >= 256 >= 36
        cpi     r16, 36
        brlo    DIV_FIM             ; byte alto = 0 e baixo < 36 -> terminou

DIV_SUBTRAI:
        subi    r16, 36
        brcc    DIV_SEM_EMPRESTIMO
        dec     r18               ; houve "borrow", ajusta byte alto
DIV_SEM_EMPRESTIMO:
        inc     r20
        rjmp    DIV_LOOP
DIV_FIM:

        pop     r1
        pop     r0
        pop     r18
        pop     r17
        pop     r16
        ret



;/////////////////// TESTE DE DISTÂNCIA /////////////////////////////

;Compara distância em cm medida com o limiar definido para determinar se o carrinho deve rotacionar, e em qual sentido (dependendo das rotações anteriores)
;Se estiver no meio de um processo de mudança de direção e não for detectado obstáculo, reinicia o movimento para frente

AVALIA_DISTANCIA:
cpi     r20, LIMIAR_CM

;Se o valor em r20 for MENOR que o limiar -> obstáculo detectado
brlo    CHANGE_DIRECTION

;Se não, limpa o registrador de rotações, reativa motores e volta ao loop principal
clr ROT_COUNT
rcall RUN_MOTORS
ret

CHANGE_DIRECTION:
rcall STOP_MOTORS  ;OBS.: AVALIAR SE É NECESSÁRIO INSERIR DELAY PARA PARAR TOTALMENTE
cpi ROT_COUNT, 0x00
breq ROTATION_1
cpi ROT_COUNT, 0x01
breq ROTATION_2
cpi ROT_COUNT, 0x02
breq ROTATION_3

;Se já estiver com o ROT_COUNT em 0x03 (encontrou obstáculo voltando a de onde veio, fica parado até detectar uma abertura)
ret	;Sem incrementar o contador de rotações


;Se ROT_COUNT for 0x00, segue no normal (ROTATION_1)
ROTATION_1:
;Gira uma vez para a esquerda
rcall TURN_LEFT
rcall WAIT_ROTATION
rcall STOP_MOTORS
rjmp END_ROT

ROTATION_2:
;Gira duas vezes para a direita (sentido oposto da primeira rotação)
rcall TURN_RIGHT
rcall WAIT_ROTATION
rcall TURN_RIGHT
rcall WAIT_ROTATION
rcall STOP_MOTORS
rjmp END_ROT

ROTATION_3:
;Gira mais uma vez para a direita, se direcionando no sentido oposto do qual veio antes da primeira detecção de obstáculo
rcall TURN_RIGHT
rcall WAIT_ROTATION
rcall STOP_MOTORS
rjmp END_ROT


END_ROT:
inc ROT_COUNT		;Aumenta o número de rotações realizadas
ret


;//////////// LOOP DE DELAY ENTRE MEDIÇÕES ////////////////////

;Implementação de delay de cooldown do sensor ultrassônico por decremento

;OBS.: COGITAR ALTERAR PARA TIMER

ESPERA_MS:
        push    r16
        push    r17
        push    r18
LOOP_MS:
        ldi     r17, 24
LOOP_4:
        ldi     r18, 250
LOOP_250:
        dec     r18
        brne    LOOP_250
        dec     r17
        brne    LOOP_4
        dec     r16
        brne    LOOP_MS
        pop     r18
        pop     r17
        pop     r16
        ret




;//////////////////// AÇÕES DOS MOTORES /////////////////////////////

;--- FRENTE: as duas rodas "para frente" (carrinho avança) --------------------
; Com motores espelhados, "ambas para frente" corresponde a rotacoes FISICAS
; opostas (uma roda horario, outra anti-horario) -> exatamente sua descricao.

RUN_MOTORS:
sbi PORTD, LIN1
cbi PORTD, LIN2
sbi PORTD, RIN1
cbi PORTD, RIN2
ret


;--- PARADO: desliga as 4 chaves (motores em roda-livre) ----------------------

STOP_MOTORS:
cbi PORTD, LIN1
cbi PORTD, LIN2
cbi PORTD, RIN1
cbi PORTD, RIN2
ret

;--- GIRO DIREITA (no proprio eixo): roda E p/ frente, roda D p/ tras ---------
; resultado: carrinho gira no sentido horario (visto de cima) = vira p/ direita

TURN_RIGHT:
sbi PORTD, LIN1
cbi PORTD, LIN2
cbi PORTD, RIN1
sbi PORTD, RIN2
ret


;--- GIRO ESQUERDA (no proprio eixo): roda E p/ tras, roda D p/ frente --------

TURN_LEFT:
cbi PORTD, LIN1
sbi PORTD, LIN2
sbi PORTD, RIN1
cbi PORTD, RIN2
ret

;--- DELAY ROTAÇÃO: espera um tempo com o motor rotacionando

WAIT_ROTATION:

clr r16
sts TCNT1H, r16
sts TCNT1L, r16     ;zera o timer 1

;ldi r16, (1<<CS12)|(1<<CS10)
ldi r16, (1<<WGM12)|(1<<CS12)|(1<<CS10)
sts TCCR1B,r16			;Configura PS 1024, iniciando contagem (interrupção no match do comparador A do timer 1)

wait_interrupt:
cpse TIMER1_FLAG, r12   ;Verifica se a interrupção foi ativada
rjmp wait_interrupt

;Após ser ativada, encerra a SR de espera, desativando o timer
clr TIMER1_FLAG
ldi r16,(1<<WGM12)
sts TCCR1B,r16
ret


;////////////////////////// SUB-ROTINAS DE INTERRUPÇÃO /////////////////////////////////

;Compare match do Timer 1 -> Delay de rotação dos motores

INT_TIMER1_COMPA:
ldi TIMER1_FLAG, 0x01  ;Sinalizador de que a interrupção foi ativada
reti


INT_RX_USART:
;Obs.: Preencher depois
nop
reti


;END
;Créditos aos magnânimos Gonlaço, FIR e MEEEEEEEEEEESTRE DARSKI
