;---------------------------------------------------------
; microwave.asm
;
; Author : HuyB
;---------------------------------------------------------

; Device constants
.nolist
.include "m328pdef.inc" ; Define device ATmega328P
.list

; General Constants
.equ CLOSED = 0
.equ OPEN = 1
.equ ON = 1
.equ OFF = 0
.equ YES = 1
.equ NO = 0
.equ JCTR = 125 ; Joystick centre value

; States
.equ STARTS = 0
.equ IDLES = 1
.equ DATAS = 2
.equ COOKS = 3
.equ SUSPENDS = 4

; Port Pins
.equ	LIGHT	= 7		; Door Light WHITE LED PORTD pin 7
.equ	TTABLE	= 6		; Turntable PORTD pin 6 PWM
.equ	BEEPER	= 5		; Beeper PORTD pin 5
.equ	CANCEL	= 4		; Cancel switch PORTD pin 4
.equ	DOOR	= 3		; Door latching switch PORTD pin 3
.equ	STSP	= 2		; Start/Stop switch PORTD pin 2
.equ	HEATER	= 0		; Heater RED LED PORTB pin 0
;---------------------------------------------------------
;                         S R A M
;---------------------------------------------------------
.dseg
.org SRAM_START
; Global Data
cstate: .byte 1 ; Current State
inputs: .byte 1 ; Current input settings
joyx: .byte 1 ; Raw joystick x-axis
joyy: .byte 1 ; Raw joystick y-axis
joys: .byte 1 ; Joystick status bits 0-not centred,1- centred
seconds: .byte 2 ; Cook time in seconds 16-bit
sec1: .byte 1 ; minor tick time (100 ms)
tascii:  .byte 8;
;---------------------------------------------------------
;                       C O D E
;---------------------------------------------------------
.cseg
.org 0x000000

jmp start

.org 0xF6

cmsg1: .db " Time: ",0
cmsg2: .db " Cook Time: ",0,0
cmsg3: .db " State: ",0,0
joymsg: .db " Joystick X:Y ",0,0

;---------------------------------------------------------
;              .asm include statements
;---------------------------------------------------------

.include "iopins.asm"
.include "util.asm"
.include "serialio.asm"
.include "adc.asm"
.include "i2c.asm"
.include "rtcds1307.asm"
.include "andisplay.asm"
start:

  ldi	r16,HIGH(RAMEND)	; Initialize the stack pointer
  out	sph,r16
  ldi r16,LOW(RAMEND)
  out	spl,r16

  call initPorts
  call initUSART0
  call initADC
  call initI2C
  call initDS1307
  call initAN
  jmp startstate


;---------------------------------------------------------
;                LOOP
;---------------------------------------------------------
loop:
  call updateTick

;---------------------------------------------------------
; 1. Door Open → jump to suspend
;---------------------------------------------------------
  sbis PIND,DOOR
  jmp suspend

;---------------------------------------------------------
; 2. Cancel Key Pressed → jump to idle
;---------------------------------------------------------
  sbis PIND,CANCEL
  jmp idle

;---------------------------------------------------------
; 3. Start/Stop Key logic
;---------------------------------------------------------
  lds  r24, cstate          ; Load current state
  sbic PIND, STSP
  jmp joy0

;---------------------------------------------------------
; 4. Start/Stop pressed → decide next state
;---------------------------------------------------------
  cpi  r24, COOKS
  breq suspend              ; (a) if currently cooking → suspend

  cpi  r24, IDLES
  breq cook                 ; (b) if idle → start cooking
  cpi  r24, SUSPENDS
  breq cook                 ;     if suspended → start cooking
  cpi  r24, STARTS
  breq cook                 ;     if starting → start cooking

  jmp loop                 ; (c) otherwise → loop

joy0:
    call joystickInputs
    lds r24, cstate       ; Get current state
    cpi r24, COOKS        ; Are we cooking?
    breq loop             ; Yes, ignore joystick during cooking
    lds r25, joys         ; Check if joystick centered
    cpi r25, 1
    breq loop             ; Centered, do nothing
    jmp dataentry         ; Not centered, go to data entry

startstate:
    ldi r24, STARTS
    sts cstate, r24

    ; set RTC time
    call setDS1307

    ; reset sec1 and seconds to 0
    ldi r24, 0
    sts sec1, r24
    sts seconds, r24
    sts seconds+1, r24

    ; turn off HEATER and LIGHT
    cbi PORTD, HEATER
    cbi PORTD, LIGHT

    jmp loop

;---------------------------------------------------------
;                State Actions Code
;---------------------------------------------------------
idle:
  ldi r24, IDLES
  sts cstate, r24

  cbi PORTB, HEATER
  cbi PORTD, LIGHT

  ; STOP VALUE (Neutral)
  ldi r16, 0x17      ; Decimal 23 (approx 1.5ms pulse = STOP)
  out OCR0A, r16      ; Sending Neutral signal stops continuous servos

  ldi r24,0
  sts seconds, r24
  sts seconds+1, r24

jmp loop

cook:
  ldi r24, COOKS
  sts cstate, r24

  sbi PORTB, HEATER
  cbi PORTD, LIGHT

  ; RUN VALUE
  ldi r16, 0x1E       ; Decimal 30 (approx 2.0ms pulse = FULL SPEED)
  out OCR0A, r16

  jmp loop

suspend:
  ldi r24, SUSPENDS
  sts cstate, r24

  cbi PORTB, HEATER
  sbi PORTD, LIGHT
  ldi r16, 0x17       ; Decimal 23 (approx 1.5ms pulse = STOP)
  out OCR0A, r16

  jmp loop

dataentry:						; data entry state tasks
	ldi	r24,DATAS			  ; Set state variable to Data Entry
	sts	cstate,r24
  ; Turn off HEATER and LIGHT
  cbi PORTD, HEATER
  cbi PORTD, LIGHT
  ldi r16, 0
    out OCR0A, r16
	lds	r26,seconds			; Get current cook time
	lds	r27,seconds+1
	lds	r21,joyx
	cpi	r21,135			  	; Check for time increment
	brsh	de1
	cpi	r27,0				    ; Check upper byte for 0
	brne	de0
	cpi	r26,0				    ; Check lower byte for 0
	breq	de2
de0:
	sbiw	r26,10			; Decrement cook time by 10 seconds
	jmp	de2
de1:
	adiw	r26,10			; Increment cook time by 10 seconds
de2:
	sts	seconds,r26			; Store time
	sts	seconds+1,r27
	call	displayState
	call	delay1s
	call	joystickInputs
	lds	r21,joys
	cpi	r21,0
	breq	dataentry			; Do data entry until joystick centred
	ldi	r24,SUSPENDS
	sts	cstate,r24
	jmp	loop


joystickInputs:
	ldi	r24,0x00		; Read ch 0 Joystick Y
	call	readADCch
	swap	r25
	lsl	r25
	lsl	r25
	lsr	r24
	lsr	r24
	or	r24,r25
	sts	joyy,r24
	ldi	r24,0x01		; Read ch 1 Joystick X
	call	readADCch
	swap	r25
	lsl	r25
	lsl	r25
	lsr	r24
	lsr	r24
	or	r24,r25
	sts	joyx,r24
	ldi	r25,0			; Not centred
	cpi	r24,115
	brlo	ncx
	cpi	r24,135
	brsh	ncx
	ldi	r25,1			; Centred
ncx:
	sts	joys,r25
ret

;---------------------------------------------------------
;                        Time Tasks
;---------------------------------------------------------

updateTick:
    call delay100ms
    cbi PORTD, BEEPER     ; Turn off beeper
    lds r22, sec1         ; Get minor tick time
    cpi r22, 10           ; 10 delays of 100 ms done?
    brne ut2
    ldi r22, 0            ; Reset minor tick
    sts sec1, r22         ; Do 1 second interval tasks
    lds r23, cstate       ; Get current state
    cpi r23, COOKS
    brne ut1
    lds r26, seconds      ; Get current cook time
    lds r27, seconds+1
    inc r26
    sbiw r26, 1           ; Decrement cook time by 1 second
    brne ut3
    jmp idle
ut3:
    sbiw r26, 1           ; Decrement/store cook time
    sts seconds, r26
    sts seconds+1, r27
ut1:
    call displayState
ut2:
    lds r22, sec1
    inc r22
    sts sec1, r22
    ret




;---------------------------------------------------------
;                   Display
;---------------------------------------------------------
displayState:
    call newline              ; Send CR + LF
;---------------------------------------------------------
;                Display the current state
;---------------------------------------------------------
    ldi r16,1
    ldi ZH,high(cmsg1<<1)
    ldi ZL,low(cmsg1<<1)
    call putsUSART0
    call displayTOD


    ldi r16,1
    ldi ZH,high(cmsg2<<1)
    ldi ZL,low(cmsg2<<1)
    call putsUSART0
    call displayCookTime

    ldi r16,1
    ldi ZH,high(cmsg3<<1)
    ldi ZL,low(cmsg3<<1)
    call putsUSART0

    lds r17,cstate
    call byteToHexASCII
    mov r16,r17
    call putchUSART0

;---------------------------------------------------------
;               Display the joystick
;---------------------------------------------------------

    ldi r16,1
    ldi ZH,high(joymsg<<1)
    ldi ZL,low(joymsg<<1)
    call putsUSART0

    lds r17,joyx
    call byteToHexASCII
    mov r16,r18
    call putchUSART0
    mov r16,r17
    call putchUSART0

    ldi r16, ':'
    call putchUSART0

    lds r17,joyy
    call byteToHexASCII
    mov r16,r18
    call putchUSART0
    mov r16,r17
    call putchUSART0


    ret

displayTOD:
    ldi  r25, HOURS_REGISTER
    call ds1307GetDateTime
    mov  r17, r24
    call pBCDToASCII
    mov  r16, r17
    call putchUSART0
    mov  r16, r18
    call putchUSART0

    ldi  r16, ':'
    call putchUSART0

    ldi  r25, MINUTES_REGISTER
    call ds1307GetDateTime
    mov  r17, r24
    call pBCDToASCII
    mov  r16, r17
    call putchUSART0
    mov  r16, r18
    call putchUSART0

    ldi  r16, ':'
    call putchUSART0

    ldi  r25, SECONDS_REGISTER
    call ds1307GetDateTime
    mov  r17, r24
    call pBCDToASCII
    mov  r16, r17
    call putchUSART0
    mov  r16, r18
    call putchUSART0

    lds r24, cstate
    cpi r24, COOKS
    breq no_an_tod
    cpi r24, SUSPENDS
    breq no_an_tod
    cpi r24, DATAS
    breq no_an_tod

    ; Display Hours
    ldi r25, HOURS_REGISTER
    call ds1307GetDateTime
    mov r17, r24
    call pBCDToASCII    ; r17=upper, r18=lower

    push r18

    mov r16, r17
    ldi r17, 0          ; Digit 0
    call anWriteDigit

    pop r16             ; FIX: Restore Lower Digit into r16 for printing
    ldi r17, 1          ; Digit 1
    call anWriteDigit

    ; Display Minutes
    ldi r25, MINUTES_REGISTER
    call ds1307GetDateTime
    mov r17, r24
    call pBCDToASCII

    push r18            ; FIX: Save r18

    mov r16, r17
    ldi r17, 2          ; Digit 2
    call anWriteDigit

    pop r16
    ldi r17, 3          ; Digit 3
    call anWriteDigit

no_an_tod:
    ret

displayCookTime:

    lds r16, seconds
    lds r17, seconds+1
    call itoa_short

    ldi r18, 0
    sts tascii+5, r18
    sts tascii+6, r18
    sts tascii+7, r18

    ldi zl, low(tascii)
    ldi zh, high(tascii)

    ldi r16, 0
    call putsUSART0

    lds r24, cstate
    cpi r24, COOKS
    breq do_an_cook
    cpi r24, SUSPENDS
    breq do_an_cook
    cpi r24, DATAS
    breq do_an_cook
    ret                   ; Return if NOT in Cook, Suspend, or Data

do_an_cook:
    lds r16,seconds       ; Get current timer seconds
    lds r17,seconds+1
    ldi r18,60            ; 16-bit Divide by 60 seconds to get mm:ss
    ldi r19,0             ; answer = mm, remainder = ss
    call div1616
    mov r4,r0             ; Save mm in r4
    mov r5,r2             ; Save ss in r5

    ; Display Minutes (Digits 0 and 1)
    mov r16,r4            ; Divide minutes by 10
    ldi r18,10
    call div88
    ldi r16,'0'           ; Convert to ASCII
    add r16,r0            ; Division answer is 10's minutes
    ldi r17,0
    call anWriteDigit     ; Write 10's minutes digit
    ldi r16,'0'           ; Convert ASCII
    add r16,r2            ; Division remainder is 1's minutes
    ldi r17,1
    call anWriteDigit     ; Write 1's minutes digit

    ; Display Seconds (Digits 2 and 3)
    mov r16,r5            ; Divide seconds by 10
    ldi r18,10
    call div88
    ldi r16,'0'           ; Convert to ASCII
    add r16,r0            ; Division answer is 10's seconds
    ldi r17,2
    call anWriteDigit     ; Write 10's seconds digit
    ldi r16,'0'           ; Convert to ASCII
    add r16,r2            ; Division remainder is 1's seconds
    ldi r17,3
    call anWriteDigit     ; Write 1's seconds digit
    ret
