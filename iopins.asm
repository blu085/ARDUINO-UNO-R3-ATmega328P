; iopins.asm
;
;   Author: HuyB
;

; Port Initialization
initPorts:

	in		r24,DDRD		; Get the contents of DDRD
	ori		r24,0b11100000	; Set Port D pins 5,6,7 to outputs
	out		DDRD,r24
	in		r24,DDRB		; Get the contents of DDRB
	ori		r24,0b00000011	; Set Port B pins 0,1 to output
	out		DDRB,r24
	in		r24,DDRD
	andi	r24,0b11100011	; Set Port D pins 2,3,4 to inputs
	out		DDRD,r24
	in		r24,PORTD		; Pull pins 2,3,4 high
	ori		r24,0b00011100
	out		PORTD,r24

; Timer0 PWM Setup
; Use Fast PWM (Mode 3) -> WGM01=1, WGM00=1
ldi r16, (1<<COM0A1)| (1<<WGM01) | (1<<WGM00)
out TCCR0A, r16

; Prescaler = 1024
ldi r16, (1<<CS02) | (1<<CS00)
out TCCR0B, r16

; Initialize to Neutral (Stop) instead of 0
ldi r16, 0x17   ; Decimal 23 (approx 1.5ms pulse = STOP)
out OCR0A, r16
ret
