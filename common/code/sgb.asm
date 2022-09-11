SGB_SEND_PACKET::
	ld   b,a
	ld   c,$00
.nextpacket
	push bc
	ld   a,$00
	ld   [$ff00+c],a
	ld   a,$30
	ld   [$ff00+c],a
	ld   b,$10
.nextbyte
	ld   e,$08
	ld	a,[hl+]
	ld   d,a
.nextbit
	bit  0,d
	ld   a,$10
	jr   nz,.is1
	ld   a,$20
.is1
	ld   [$ff00+c],a
	ld   a,$30
	ld   [$ff00+c],a
	rr   d
	dec  e
	jr   nz,.nextbit
	dec  b
	jr   nz,.nextbyte
	ld   a,$20
	ld   [$ff00+c],a
	ld   a,$30
	ld   [$ff00+c],a

	call	SGB_PACKETDELAY

	pop  bc
	dec  b
	ret  z

	jr	.nextpacket

SGB_PACKETDELAY::
	ld   de,$1B58
.delayloop
	nop  
	nop  
	nop  
	dec  de
	ld   a,d
	or   e
	jr   nz,.delayloop
	ret  

; Returns A=0 if not SGB, or A=1 if SGB.
SGB_TEST::
	ld	A,1
	ld	HL,MLT_REQ
	call	SGB_SEND_PACKET

	ldh	A,[$FF00]
	and	$03
	cp	$03
	jr	nz,.sgb_detected

	ld	A,$20
	ldh	[$FF00],A
	push	AF
	pop	AF
	ld	A,$30
	ldh	[$FF00],A
	ld	A,$10
	ldh	[$FF00],A
	push	AF
	pop	AF
	push	AF
	pop	AF
	ld	A,$30
	ldh	[$FF00],A
	push	AF
	pop	AF
	push	AF
	pop	AF
	ldh	A,[$FF00]
	and	$03
	sub	$03
	jr	nz,.sgb_detected

	ret
.sgb_detected
	ld	A,1
	ld	HL,MLT_REQ_DISABLE
	call	SGB_SEND_PACKET
	ld	A,1
	ret

MLT_REQ::
	DB $89,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

MLT_REQ_DISABLE::
	DB $89,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
