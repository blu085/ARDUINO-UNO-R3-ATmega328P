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

; Timer1 Interrupt Setup For Tick
; f = clk / (2 * N * (1 + K)) ATMega328P clk = 16 MHz
; Pre-scalar N = 1024
ldi r20,0x00
sts TCCR1A,r20 ; CTC timer1
ldi r20,high(1562) ; 100 msec tick
sts OCR1AH,r20
ldi r20,low(1562)
sts OCR1AL,r20
ldi r16,1<<OCIE1A
sts TIMSK1,r16 ; Enable Timer1 compare match interrupt
sei ; Enable interrupts globally
ldi r20,0x0d
sts TCCR1B,r20 ; Prescaler 1024, CTC mode, start timer

ret
