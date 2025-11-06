;
; util.asm
;
;   Author: HuyB
;

; 100 ms Delay
delay100ms:
	ldi	r18, 0xFF	; 255
	ldi	r24, 0xE1	; 225
	ldi	r25, 0x04	; 
d100:
	subi	r18, 0x01	; 1
	sbci	r24, 0x00	; 0
	sbci	r25, 0x00	; 0
	brne	d100
	ret

; Packed BCD To ASCII
; Number to convert in r17
; Converted output in r17 (upper nibble),r18 (lower nibble)
pBCDToASCII:

  mov r18,r17
  andi r18,0x0f
  ori r18,0x30

  swap r17
  andi r17,0x0f
  ori r17,0x30
ret

; Byte To Hexadecimal ASCII
; Number to convert in r17
; Converted output in r17 (lowernibble),r18 (upper nibble)
byteToHexASCII:

  mov r18,r17
  andi r17,0x0f
  ldi r16,0x30
  cpi r17,10
  brlo low_lower
  ldi r16,0x37
low_lower:
  add r17,r16

  swap r18
  andi r18,0x0f
  ldi r16,0x30
  cpi r18,10
  brlo low_upper
  ldi r16,0x37
low_upper:
  add r18,r16
ret
