.include "m328Pdef.inc"
.org 0x0000

;//////////////// DEFINIÇÃO DE CONSTANTES /////////////////////

;baud-rate

.equ UBRR_VAL = 103 ; define constante representando o baud rate da comunicação UART em 9600bps
                    ; UBRR_VAL = (f_clk/(16*baud_rate)) - 1
;comandos

.equ CMD_FORWARD    = 0x46     ; F
.equ CMD_BACK       = 0x42     ; B
.equ CMD_LEFT       = 0x4C     ; L
.equ CMD_RIGHT      = 0x52     ; R
.equ CMD_STOP       = 0x53     ; S
.equ CMD_SPEED_UP   = 0x2B     ; +
.equ CMD_SPEED_DOWN = 0x2D     ; -


;////////////// CONFIGURAÇÕES /////////////////////////////////


;Inicialização SP
ldi     R16,LOW(RAMEND)
out     SPL,R16
ldi     R16,HIGH(RAMEND)
out     SPH,R16

;Configura porta B como saída para exibir o caracter recebido
ser     r16
out     DDRB,r16; configura todos os pinos da porta B como saída
clr     r16
out     PORTB,r16

;Inicialização comunicação USART

;Configuração baud rate (taxa de comunicação -> 9,6 kbps)
ldi     r16,HIGH(UBRR_VAL)
sts     UBRR0H,r16
ldi     r16,LOW(UBRR_VAL)
sts     UBRR0L,r16

;Habilitação do RX do UART0
ldi     r16,(1<<RXEN0);Criação de máscara que seta '1' na posição do bit RXEN0
sts     UCSR0B,r16

;Configuração do formato do frame de comunicação
ldi     r16,(1<<UCSZ01) | (1<<UCSZ00)
sts     UCSR0C,r16;Seta os bits 2:1, definindo tamanho de caracter para 8 bits
                  ;Configura modo assíncrono (bit7:bit6 = 00)
                  ;Modo de paridade desabilitado (bit5:bit4 = 00)

;///////////////////// MAIN ///////////////////////////////

;Loop que aguarda chegar alguma instrução do controle bluetooth

main:
lds     r16,UCSR0A
sbrs    r16, RXC0     ;Pula para a leitura do dado caso haja dados no buffer a serem lidos (RXC0 set) -> Pode gerar interrupção
rjmp    main         ;Reinicia

;Trocar por vetor de interrupção USART_RXC
;Leitura do dado
lds     r17,UDR0      ;Registrador que armazena o dado recebido por RX0
out     PORTB,r17     ;Joga o dado lido nos leds da porta B
rcall   process_command
rjmp main



;////////////// SR DE PROCESSAMENTO DO SINAL ////////////////////////////

process_command:

ldi     ZL,low(command_table << 1)
ldi     ZH,high(command_table <<1) ;Carrega o endereço da tabela de comandos no ponteiro Z
                                   ;multiplicamos o endereço por 2 (<< 1) porque a Flash é organizada em Words (16 bits)

search_loop:

lpm   r18,Z+   ;Lê o caracter da tabela e incrementa o ponteiro Z

cpi   r18,0X00 ;Determina se chegou no fim da tabela (null terminator)
breq  invalid_command

cp    r18,r17  ;Compara o caracter da tabela com o recebido
breq  found_command

adiw  ZL, 3        ;Se ainda não deu match, segue percorrendo a tabela após incrementar o ponteiro em 3 bytes
rjmp  search_loop

invalid_command:
ret

found_command:
adiw  ZL,1        ;Pula o byte de padding (0xFF)
lpm   r20,Z+      ;Salva byte alto do endereço da SR em r20
lpm   r19,Z       ;Salva byte baixo do endereço da SR em r19

mov ZH, R20
mov ZL, R19

ijmp              ;Salta para o endereço em Z (subrotina da ação dos motores)

ret


;////////////// LOOKUP TABLE DOS COMANDOS ///////////////////////////

command_table:

.db CMD_FORWARD,    0xFF, high(run_forward), low(run_forward)
.db CMD_BACK,       0xFF, high(run_back),    low(run_back)
.db CMD_LEFT,       0xFF, high(turn_left),   low(turn_left)
.db CMD_RIGHT,      0xFF, high(turn_right),  low(turn_right)
.db CMD_STOP,       0xFF, high(motor_stop),  low(motor_stop)
.db CMD_SPEED_UP,   0xFF, high(speed_up),    low(speed_up)
.db CMD_SPEED_DOWN, 0xFF, high(speed_down),  low(speed_down)

.db 0x00,0x00       ;demarcador de fim da tabela



;/////////// SUBROTINAS DE EXECUÇÃO DOS COMANDOS ///////////////////

run_forward:
nop
ret

run_back:
nop
ret

turn_left:
nop
ret

turn_right:
nop
ret

motor_stop:
nop
ret

speed_up:
nop
ret

speed_down:
nop
ret

;Após todas as subrotinas, volta para onde o rcall foi chamado e reinicia o loop de aquisição









