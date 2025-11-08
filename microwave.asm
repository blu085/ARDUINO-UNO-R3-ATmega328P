; microwave.asm
;
; Author : HuyB
;

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

cmsg1: .db " Time: ",0,0
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
call updateTick ; Check the time
call joystickInputs

; Check the inputs here
; If Door Open jump to suspend
sbis PIND,DOOR
jmp suspend

; Cancel Key Pressed
sbis PIND,CANCEL
jmp dataentry

; Start Stop Key Pressed
sbic PIND,STSP
jmp cook

; State Actions Code

idle: ldi r24,IDLES ; Set state variable to Idle
sts cstate,r24 ; Do idle state tasks
jmp loop

; Cook State
cook: ldi r24,COOKS ; Set state variable to Cook
sts cstate,r24 ; Do cook state tasks
jmp loop

; Suspend State
suspend: ; suspend state tasks
ldi r24,SUSPENDS ; Set state variable to Suspend
sts cstate,r24 ; Do suspend state tasks
jmp loop

; Data Entry State
dataentry: ; data entry state tasks
ldi r24,DATAS ; Set state variable to Suspend when done
sts cstate,r24
jmp loop

startstate: ; start state tasks
ldi r24,STARTS ; Start state
sts cstate,r24

ldi     r16, 10        ; low byte of 16-bit seconds
sts     seconds, r16
ldi     r16, 0         ; high byte = 0
sts  seconds+1, r16
call setDS1307

jmp loop

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
updateTick: ; Time tasks
lds r22,sec1 ; Get minor tick time
cpi r22,10 ; 10 delays of 100 ms done?
brne ut2
ldi r22,0 ; Reset minor tick
sts sec1,r22 ; Do 1 second interval tasks

call displayTOD
call displayCookTime
call displayState

ut2: lds r22,sec1
inc r22
sts sec1,r22
call delay100ms

ret


;---------------------------------------------------------
;                   Display
;---------------------------------------------------------
displayState:
    call newline              ; Send CR + LF
;---------------------------------------------------------
;                Display the current state
;---------------------------------------------------------
    ldi r16,1                 ; String in program memory
    ldi ZH,high(cmsg3<<1)     ; Load address of stmsg
    ldi ZL,low(cmsg3<<1)
    call putsUSART0           ; Print "current state at: "

    lds r17,cstate            ; Load current state value
    call byteToHexASCII       ; Convert to ASCII
    mov r16,r17               ; Lower nibble
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

    ldi r16,1                 ; String in program memory
    ldi ZH,high(cmsg2<<1)     ; Load address of stmsg
    ldi ZL,low(cmsg2<<1)
    call putsUSART0

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

    ldi r16,1                 ; String in program memory
    ldi ZH,high(cmsg1<<1)     ; Load address of stmsg
    ldi ZL,low(cmsg1<<1)
    call putsUSART0

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

