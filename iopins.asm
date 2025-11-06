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
	andi		r24,0b11100011	; Set Port D pins 2,3,4 to inputs
	out		DDRD,r24
	in		r24,PORTD		; Pull pins 2,3,4 high
	ori		r24,0b00011100
	out		PORTD,r24
ret
