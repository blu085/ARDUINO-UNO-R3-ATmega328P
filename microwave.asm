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
  lds r24, cstate
  cpi r24, COOKS
  breq loop
  lds r25, joys
  cpi r25, 1
  breq loop
  jmp dataentry

;---------------------------------------------------------
;                State Actions Code
;---------------------------------------------------------
idle:

  ldi r24, IDLES
  sts cstate, r24

  ldi r16,0
  out OCR0A, r16

  cbi PORTB, HEATER
  cbi PORTD, LIGHT

  ldi r16,0
  sts seconds, r16
  sts seconds+1, r16


jmp loop

cook:

  ldi r24, COOKS
  sts cstate, r24

  ldi r16, 0x23
  out OCR0A, r16

  sbi PORTB, HEATER
  cbi PORTD, LIGHT

  jmp loop

suspend:
  ldi r24, SUSPENDS
  sts cstate, r24

  ldi r16, 0
  out OCR0A, r16

  cbi PORTB, HEATER
  sbi PORTD, LIGHT

  jmp loop

dataentry:

  ldi	r24,DATAS			; Set state variable to Data Entry
	sts	cstate,r24

  cbi PORTB, HEATER
  cbi PORTD, LIGHT



	lds	r26,seconds			; Get current cook time
	lds	r27,seconds+1
	lds	r21,joyx
	cpi	r21,135				; Check for time increment
	brsh	de1
	cpi	r27,0				; Check upper byte for 0
	brne	de0
	cpi	r26,0				; Check lower byte for 0
	breq	de2
de0:
	sbiw	r27:r26,10			; Decrement cook time by 10 seconds
	jmp	de2
de1:
	adiw	r27:r26,10			; Increment cook time by 10 seconds
de2:
	sts	seconds,r26			; Store time
	sts	seconds+1,r27
	call	displayState
	call	delay1s
	call	joystickInputs
	lds	r21,joys
	cpi	r21,0
	breq	dataentry			; Do data entry until joystick centred
	ldi r24, SUSPENDS
  sts cstate, r24
  jmp loop

startstate:
  ldi r24, STARTS
  sts cstate, r24

  ; reset seconds and minor tick, turn off heater & light
  ldi r16, 0
  sts sec1, r16
  sts seconds, r16
  sts seconds+1, r16
  cbi PORTB, HEATER
  cbi PORTD, LIGHT

  call setDS1307

  jmp loop

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
  cbi PORTD, BEEPER
  lds r22,sec1 ; Get minor tick time
  cpi r22,10 ; 10 delays of 100 ms done?
  brne ut2

  ldi r22,0 ; Reset minor tick
  sts sec1,r22 ; Do 1 second interval tasks

   ; (2) Check state
    lds r24,cstate
    cpi r24,COOKS
    brne ut_display           ; if not COOKS, skip countdown

    ; (3) Load 16-bit seconds
    lds r16,seconds
    lds r17,seconds+1

    ; check if seconds = 0
    or  r16,r17
    breq ut_idle              ; if 0, jump to idle

    ; otherwise decrement
    subi r16,1
    sbci r17,0
    sts seconds,r16
    sts seconds+1,r17

    jmp ut_display           ; fall through to display

ut_idle:
    jmp idle                 ; go to idle state

ut_display:
    call displayState         ; show updated info

ut2:
  lds r22,sec1
  inc r22
  sts sec1,r22
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

    ret

