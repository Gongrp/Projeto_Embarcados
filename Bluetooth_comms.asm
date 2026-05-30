.include m328Pdef.inc
.org 0x0000

.equ UBRR_VAL = 103 ; define constante representando o baud rate da comunicação UART em 9600bps
                    ; UBBR_VAL = (f_clk/(16*baud_rate)) - 1
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

;Configuração baud rate (taxa de comunicação -> 9,6 kHz ou kbps)
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

;Loop que aguarda chegar alguma instrução do controle bluetooth
loop:
lds     r16,UCSR0A
sbrs    r16, RXC0     ;Pula para a leitura do dado caso haja dados no buffer a serem lidos (RXC0 set) -> Pode gerar interrupção
rjmp    loop          ;Reinicia

;Leitura do dado e exibição na portaB
lds     r17,UDR0      ;Registrador que armazena o dado recebido por RX0
out     PORTB,r17     ;Joga o dado lido nos leds da porta B
rjmp    loop          ;Reinicia loop



