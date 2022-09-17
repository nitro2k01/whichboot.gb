include "incs/hardware.inc"

; Load a r16 with a pointer to map at coordinate x,y
; LDXY r16, x, y
LDXY:	MACRO
	ld	\1,($9800+(\2)+32*(\3))
	ENDM

; Emit GBC palette entry.
; The color components are 5 bit. (0-31)
; PAL_ENTRY R,G,B
PAL_ENTRY:	MACRO
	assert (\1)==(\1)&%11111
	assert (\2)==(\2)&%11111
	assert (\3)==(\3)&%11111
	dw	(\1) | (\2)<<5| (\3)<<10
ENDM

; VRAM platform detection constants.
VPLATB_NULLBAD	equ 7
VPLATF_NULLBAD	equ 1<<VPLATB_NULLBAD

VPLATF_LOGO_NULL	equ 0
VPLATF_LOGO_NINTENDO	equ 1
VPLATF_LOGO_LOADING	equ 2
VPLATF_LOGO_UNKNOWN	equ 3

VPLATF_MAP_NULL	equ 0<<2
VPLATF_MAP_OK_WITH_R	equ 1<<2
VPLATF_MAP_OK_NO_R	equ 2<<2
VPLATF_MAP_UNKNOWN	equ 3<<2

VPLATF_R_NULL		equ 0<<4
VPLATF_R_CORRECT	equ 1<<4
VPLATF_R_UNKNOWN	equ 2<<4

SECTION "Entry point 0000", ROM0[$0]
	; Support execution from address 0. (For use with boot ROM skip.)
	di				; 1
	jp	ENTRY.entry0		; 4

SECTION "Rst08", ROM0[$8]
	ret
SECTION "Rst10", ROM0[$10]
	ret
SECTION "Rst18", ROM0[$18]
	ret
SECTION "Rst20", ROM0[$20]
	ret
SECTION "Rst28", ROM0[$28]
	ret
SECTION "Rst30", ROM0[$30]
	ret
SECTION "Rst38", ROM0[$38]
:
	ld	b,b
	jr	:-

SECTION "int_vbl", ROM0[$40]
	reti
SECTION "int_lcd", ROM0[$48]
	reti
SECTION "int_timer", ROM0[$50]
	reti
SECTION "int_serial", ROM0[$58]
	reti
SECTION "int_joy", ROM0[$60]
	reti

SECTION "Header", ROM0[$100]
	di				; 1
	jp	ENTRY			; 4

	ds	$150 - @, 0		; Fill up the header area and let rgbfix deal with it.

SECTION "Main", ROM0
ENTRY::
	ld	[RegStorage.sp], SP	; 5 Store SP
	ld	SP,RegStorage.top	; 3 Store the other regs using the stack
	push	AF			; 4
	push	BC			; 4
	push	DE			; 4
	push	HL			; 4

	ld	SP,Stack.top		; 3
	call	CAPTURE_LY_AND_DIV	; CAPTURE_LY_AND_DIV takes the call into account.

	xor	A			; Signal that we started from the normal entry point.
	jr	.after_capture
	; Entry point if PC started at 0. It's easier to just duplicate a few bytes of code
	; instead of dealing with offsetting the timing measurement.
.entry0
	ld	[RegStorage.sp], SP	; 5 Store SP
	ld	SP,RegStorage.top	; 3 Store the other regs using the stack
	push	AF			; 4
	push	BC			; 4
	push	DE			; 4
	push	HL			; 4

	ld	SP,Stack.top		; 3
	call	CAPTURE_LY_AND_DIV	; CAPTURE_LY_AND_DIV takes the call into account.

	ld	A,1			; Signal that we started from entry point 0.
.after_capture
	ld	[platform_start0],A
	ldh	A,[div_acc_store]
	inc	A			; A==$FF?
	jr	z,.acc_error_nomath	; Don't do math on the fractional part if it indicates an invalid value.

	; First 1 compensates for inc above. ($FF test.)
	sub	1+1+4+5+3+4+4+4+4+3	; Subtract the time for the code executed before CAPTURE_LY_AND_DIV
	jr	nc,.nocarry
	ld	HL,div_store
	dec	[HL]
.nocarry
	and	$3f			; Modulo to 0-$3F again
.store_acc
	ldh	[div_acc_store],A
.acc_error_nomath

	; Turn off LCD.
	ldh	A,[rLCDC]
	add	A
	jr	nc,.alreadyoff
.waitvbl
	ldh	A,[rLY]
	cp	$90
	jr	c,.waitvbl

.alreadyoff
	xor	A
	ldh	[rLCDC],A

	; Detect platform heuristically
	ld	B,0			; Temp storage for the heuristic platform flag.
	ldh	A,[RegStorage.a]
	cp	$11
	jr	nz,.notgbc
	set	1,B			; Set GBC flag
	ldh	A,[RegStorage.b]
	dec	A			; B==1? (GBA)
	jr	nz,.platform_done
	set	0,B			; Set alternate flag
	jr	.platform_done
.notgbc
	inc	A			; A==$FF? (GBP/SGB2)
	jr	nz,.platform_done
	set	0,B			; Set alternate flag
.platform_done
	push	BC
	call	SGB_TEST		; Returns A==0 or A==1
	add	A			; %10
	add	A			; %100
	pop	BC
	add	B			; Add previous value

	ldh	[platform_heur],A

	; This needs to be done before overwriting VRAM.
	call	DETECT_VRAM_PLATFORM

	; GBC initialization
	ldh	A,[platform_heur]
	bit	1,A			; Check for GBC mode in the heuristic match.
	jr	nz,.initgbc

	ldh	A,[platform_start0]	; Check if we entered from 0. In this case still perform GBC init.
	or	A
	jr	z,.noinitgbc
.initgbc
	; GBC init
	ld	A,1
	ldh	[rVBK],A

	; Clear the attribute map for BG 1.
	ld	HL,$9800
	ld	B,$9C			; Top byte of end address
	ld	E,L			; L==0
	call	FASTCLEAR

.noinitgbc
	; Do a couple of GBC related init tasks even though we're (supposedly) not in GBC mode.
	; This is insurance that we're able to show things on screen even if we detect the CPU
	; mode incorrectly somehow. In other case, these are NOPs.

	; Restore VRAM bank.
	xor	A
	ldh	[rVBK],A

	; Load one palette so text is visible
	ld	BC,8<<8|LOW(rBCPS)
	ld	HL,GbcPals
	ld	A,$80
	ld	[$FF00+C],A
	inc	C
.palloop
	ld	A,[HL+]
	ld	[$FF00+C],A
	dec	B
	jr	nz,.palloop


	; Clear the tile map for BG 1.
	ld	HL,$9800
	ld	B,$9C			; Top byte of end address.
	ld	E," "			; Fill with map with spaces because tile $00 is left uninitialized.
	call	FASTCLEAR

	; Load a font into tile RAM.
	ld	HL,Font0
	ld	DE,$8200
	ld	BC,Font0.end-Font0
	call	COPY

	; Print the static text portion of the UI.
	ld	HL,S_ALL
	LDXY	DE,0,0
	call	MPRINT

	; Load the map data for showing the logo.
	; This can't be done by MPRINT since \n is a control char.
	ld	HL,LOGO_MAP_1
	LDXY	DE,5,6
	ld	BC,$D
	call	COPY

	;ld	HL,LOGO_MAP_2		; LOGO_MAP_1 and LOGO_MAP_2 are consecutive.
	LDXY	DE,5,7
	ld	BC,$C
	call	COPY

	; Print the initial values of the CPU registers.
	; AF
	LDXY	HL,$7,$1
	ldh	A,[RegStorage.af+1]
	call	PRINTHEX
	ldh	A,[RegStorage.af]
	call	PRINTHEX

	; BC
	LDXY	HL,$F,$1
	ldh	A,[RegStorage.bc+1]
	call	PRINTHEX
	ldh	A,[RegStorage.bc]
	call	PRINTHEX

	; DE
	LDXY	HL,$7,$2
	ldh	A,[RegStorage.de+1]
	call	PRINTHEX
	ldh	A,[RegStorage.de]
	call	PRINTHEX

	; HL
	LDXY	HL,$F,$2
	ldh	A,[RegStorage.hl+1]
	call	PRINTHEX
	ldh	A,[RegStorage.hl]
	call	PRINTHEX


	; SP
	LDXY	HL,$7,$3
	ldh	A,[RegStorage.sp+1]
	call	PRINTHEX
	ldh	A,[RegStorage.sp]
	call	PRINTHEX

	; Print LY and DIV.
	LDXY	HL,4,5
	ldh	A,[ly_store]
	call	PRINTHEX

	LDXY	HL,$B,5
	ldh	A,[div_store]
	call	PRINTHEX

	; Print the fractional part of LY, or an error message if invalid.
	LDXY	HL,$E,5
	ldh	A,[div_acc_store]
	cp	$ff
	jr	z,.acc_error
	call	PRINTHEX
	jr	.after_acc_error
.acc_error
	; Timer error! (Can happen on very inaccurate emulators.)
	ld	D,H
	ld	E,L
	ld	HL,S_ERROR
	call	MPRINT

.after_acc_error
	call	DETECT_PLATFORM
	call	DETECT_TIMING_PLATFORM

	; Print platform name derived from exact register detection.
	ldh	A,[platform_exact]
	ld	HL,S_INVALID			; Check for invalid platform value. (Should never happen.)
	cp	(REG_REFERENCES.end-REG_REFERENCES)/10+1
	jr	nc,.print_exact_platform

	ld	HL,PLATFORM_EXACT_NAMES


	call	GET_STRING_FROM_INDEX
.print_exact_platform
	LDXY	DE,1,$B
	call	MPRINT


	; If we started from address 0, show this instead. (Heuristic match is useless in this case anyway.)
	ldh	A,[platform_start0]
	ld	HL,S_START0
	or	A
	jr	nz,.print_heur_platform

	; Print platform name derived from heuristics.
	ldh	A,[platform_heur]
	ld	HL,S_INVALID			; Check for invalid platform value. (Should never happen.)
	cp	8
	jr	nc,.print_heur_platform

	ld	HL,PLATFORM_HEUR_NAMES
	call	GET_STRING_FROM_INDEX

.print_heur_platform
	LDXY	DE,1,9
	call	MPRINT

	; Print platform name derived from boot timings.
	ldh	A,[platform_timing]
	ld	HL,S_INVALID			; Check for invalid platform value. (Should never happen.)
	cp	(TIMING_REFERENCES.end-TIMING_REFERENCES)/3+2
	jr	nc,.print_timing_platform

	ld	HL,PLATFORM_TIMING_NAMES
	call	GET_STRING_FROM_INDEX

.print_timing_platform
	LDXY	DE,1,$D
	call	MPRINT

	; Print logo info
	ldh	A,[platform_vram]
	and	$03
	ld	HL,PLATFORM_VRAM_NAMES

	call	GET_STRING_FROM_INDEX
	LDXY	DE,0,$F
	call	MPRINT

	; Print map info
	ldh	A,[platform_vram]
	rra
	rra
	and	$03
	ld	HL,PLATFORM_VRAM_MAP_NAMES

	call	GET_STRING_FROM_INDEX
	LDXY	DE,5,$10
	call	MPRINT

	; Print (R) info
	ldh	A,[platform_vram]
	swap	A
	and	$03
	ld	HL,PLATFORM_VRAM_R_NAMES

	call	GET_STRING_FROM_INDEX
	LDXY	DE,$C,$11
	call	MPRINT


	; Print VRAM null info
	ldh	A,[platform_vram]
	add	A
	ld	HL,S_OK
	jr	nc,:+
	ld	HL,S_BAD
:	LDXY	DE,6,$11
	call	MPRINT

	; Initialize DMG palettes.
	ld	A,%11100100
	ldh	[rBGP],A
	ldh	[rOBP0],A
	ldh	[rOBP1],A

	; Enable LCD.
	ld	A,$91
	ld	[rLCDC],A

	xor	A
	ldh	[rIF],A		; Clear pending interrupt flags.
	inc	A
	ldh	[rIE],A		; Enable only VBlank interrupt.
	;ei

.el
	halt
	jr	.el

DETECT_PLATFORM:
	ld	HL,REG_REFERENCES
	assert	(REG_REFERENCES.end-REG_REFERENCES) % 10==0
	ld	A,10		; 10=number of bytes to compare
	ldh	[temp1],A

	ld	A,LOW(RegStorage)	; Address in HRAM where test data is stored.
	ldh	[temp2],A

	ld	A,(REG_REFERENCES.end-REG_REFERENCES)/10
	ldh	[temp3],A
	call	SEARCH_LIST
	ldh	[platform_exact],A

	ret

SEARCH_LIST:
	ldh	A,[temp3]
	ld	E,A
.compareloop
	ld	D,0
	ldh	A,[temp1]			; Reload item length.
	ld	B,A
	ldh	A,[temp2]			; Reload item test data address.
	ld	C,A

.comparestringloop
	ld	A,[$FF00+C]
	sub	[HL]
	jr	z,.bytematch
	ld	D,A				; This is nonzero if bytes differ
.bytematch
	inc	HL
	inc	C
	dec	B
	jr	nz,.comparestringloop

	ld	A,D				; Do we have a match?
	or	A
	jr	z,.returnvalue
	
	dec	E
	jr	nz,.compareloop

.returnvalue
	ldh	A,[temp3]			; Length-A
	sub	E
	ret

; Check if all values in a certain memory area are set to a certain value. 
; HL=Start address.
; BC=Max length to check.
;  E=Value to check for.
; Returns A==00, z=1 if all values match or else A!=00, z=0
CHECK_IF_ALL_VALUE:
	ld	A,[HL+]
	sub	E			; Produce non-zero value if comparison fails.
	ret	nz
	dec	BC
	ld	A,B
	or	C
	jr	nz,CHECK_IF_ALL_VALUE
	ret				; A==00, z=1 from or C.

; Check if two strings match exactly, for the full specified length.
; HL=String 1.
; DE=String 2.
; BC=Max length to check.
; Returns A==00, z=1 if strings match or else A!=00, z=0
BIN_CMP:
	ld	A,[DE]
	sub	[HL]			; Produce non-zero value if comparison fails.
	ret	nz
	inc	HL
	inc	DE
	dec	BC
	ld	A,B
	or	C
	jr	nz,BIN_CMP
	ret				; A==00, z=1 from or C.


DETECT_VRAM_PLATFORM:
	; First check all areas of VRAM that should be 00 on all platforms.
	ld	HL,$8000		; Null tile.
	ld	BC,$10
	ld	E,L			; L==0
	call	CHECK_IF_ALL_VALUE
	jr	nz,.nullfail

	ld	HL,$81A0		; Upper tiles, beginning of map.
	ld	BC,$9904-$81A0
	call	CHECK_IF_ALL_VALUE
	jr	nz,.nullfail

	ld	HL,$9911		; Map, between upper and lower part of the logo.
	ld	BC,$9924-$9911
	call	CHECK_IF_ALL_VALUE
	jr	nz,.nullfail

	ld	HL,$9930		; Map, after logo and to the end of the map.
	ld	BC,$A000-$9930
	call	CHECK_IF_ALL_VALUE
	jr	nz,.nullfail
	jr	.write_vplat1		; A==0 if we're here.
.nullfail
	ld	A,VPLATF_NULLBAD	; Invalid null error.
.write_vplat1
	ldh	[platform_vram],A

	; Check if logo in map area is empty.
	LDXY	HL,4,8		; Logo map top row.
	ld	BC,$C
	call	CHECK_IF_ALL_VALUE
	jr	nz,.logo_map_is_nonempty

	LDXY	HL,4,9		; Logo map bottom row.
	ld	BC,$C
	call	CHECK_IF_ALL_VALUE
	jr	nz,.logo_map_is_nonempty
	; No Changes necessary to platform_vram. Just continue.
	jr	.logo_map_is_empty
.logo_map_is_nonempty
	LDXY	HL,4,9		; Logo map bottom row.
	ld	DE,LOGO_MAP_2
	ld	BC,$C		; Length of one row of logo map data.
	call	BIN_CMP
	ld	B,VPLATF_MAP_UNKNOWN
	jr	nz,.commit_map_value

	LDXY	HL,4,8		; Logo map top row.
	ld	DE,LOGO_MAP_1	; Top row reference
	ld	BC,$D		; Length of one row of logo map data, +1 for (R).
	call	BIN_CMP
	ld	B,VPLATF_MAP_OK_WITH_R
	jr	z,.commit_map_value
	ld	B,VPLATF_MAP_OK_NO_R
	dec	C		; Check if we were one off from matching, meaning missing (R)
	jr	z,.commit_map_value

	ld	B,VPLATF_MAP_UNKNOWN
.commit_map_value
	ldh	A,[platform_vram]
	or	B
	ldh	[platform_vram],A
.logo_map_is_empty

	; Check if (R) tile is empty.
	ld	HL,$8190		; (R) tile.
	ld	BC,$10
	ld	E,0
	call	CHECK_IF_ALL_VALUE
	jr	z,.r_tile_is_empty

	; Check if (R) tile has standard value.
	ld	HL,$8190		; (R) tile.
	ld	DE,VRAM_COPYRIGHT
	ld	BC,$10

	call	BIN_CMP
	ld	B,VPLATF_R_CORRECT
	jr	z,.commit_r_value
	ld	B,VPLATF_R_UNKNOWN


.commit_r_value
	ldh	A,[platform_vram]
	or	B
	ldh	[platform_vram],A
.r_tile_is_empty

	; Check if logo area is empty.
	ld	HL,$8010		; Logo tiles.
	ld	BC,$180
	call	CHECK_IF_ALL_VALUE
	ret	z

	; Check for standard Nintendo logo
	ld	HL,$8010		; Logo tiles.
	ld	DE,VRAM_LOGO_NINTENDO
	call	BIN_CMP
	jr	nz,:+
	ldh	A,[platform_vram]
	or	VPLATF_LOGO_NINTENDO
	ldh	[platform_vram],A
	ret
:
	
	; Check for "Loading..." (MaxStation clone logo.)
	ld	HL,$8010		; Logo tiles.
	ld	DE,VRAM_LOGO_LOADING
	call	BIN_CMP
	jr	nz,:+
	ldh	A,[platform_vram]
	or	VPLATF_LOGO_LOADING
	ldh	[platform_vram],A
	ret
:

	ldh	A,[platform_vram]
	or	VPLATF_LOGO_UNKNOWN
	ldh	[platform_vram],A
	ret

DETECT_TIMING_PLATFORM:
	ld	HL,TIMING_REFERENCES
	assert	(TIMING_REFERENCES.end-TIMING_REFERENCES) % 3==0
	ld	A,3		; 3=number of bytes to compare
	ldh	[temp1],A

	ld	A,LOW(ly_store)	; Address in HRAM where test data is stored.
	ldh	[temp2],A

	ld	A,(TIMING_REFERENCES.end-TIMING_REFERENCES)/3
	ldh	[temp3],A
	call	SEARCH_LIST
	ldh	[platform_timing],A

	; Manually detect SGB since SGB has a range of possible values 
	; $00,$D9,$01-08
	ldh	A,[ly_store]
	or	A
	ret	nz

	ldh	A,[div_store]
	cp	$D8
	ret	nz

	ldh	A,[div_acc_store]
	sub	$12		; $12-19 -> 0-7
	;dec	A		; 1-8 -> 0-7
	and	$38
	ret	nz

	ld	A,(TIMING_REFERENCES.end-TIMING_REFERENCES)/3+1
	ldh	[platform_timing],A

	ret

; Capture timing related information.
; This routine reads and stores LY.
; It then reads and stores DIV, and derives the hidden fractional part of DIV.
;
; It does this by periodically checking whether DIV ticked, with a period of 65 M cycles.
; Since (the visible portion of) DIV ticks every 64 M cycles, each loop iteration is
; progreesively offset by 1 cycle.
;
; Since there's a 2 M cycle window between read 1 and read 2, a tick will be observed for
; two consecutive loop iterations. The code following the capture sanity checks the 
; captured data and (if ok) derives the fractional part of DIV.
;
; The value it measures and calculates is the value of the visible and fractional part of DIV
; as if "call CAPTURE_LY_AND_DIV" was replaced with the "ld A,[HL]" that's reading DIV initially.
CAPTURE_LY_AND_DIV:
	ldh	A,[rLY]
	ldh	[ly_store],A

	; For testing single M cycle timing shifts.
;	rept $1d
;	nop
;	endr
	ld	HL,rDIV
	ld	A,[HL]
	ldh	[div_store],A

	ld	DE,SCRATCH
	ld	C,$40	; C=loop counter
.captureloop
	; Check whether DIV ticked between read 1 and read 2.
	; If the values are equal, the DIV1-DIV2=0.
	; If DIV ticked, DIV1-DIV2=$FF.
	ld	A,[HL]			; 2
	sub	[HL]			; 2

	ld	[DE],A			; 2
	inc	DE			; 2

	ld	B,13			; 2
.waitloop
	dec	B			; 1
	jr	nz,.waitloop		; 3/2
	;13*4-1=51

	dec	C			; 1
	jr	nz,.captureloop		; 3 (taken)
	; 2+2+2+2+2+51+1+3=65

	; Sanity check
	ld	HL,SCRATCH
	ld	C,$40
	ld	E,0			; Number of zeros.
.sanityloop
	ld	A,[HL+]
	or	A	
	jr	z,.zero
	inc	A			; Check for FF, the only allowed nonzero value.
	jr	nz,.badvalue
	dec	E			; Reverse the effect of the next dec.
.zero
	inc	E
	dec	C
	jr	nz,.sanityloop
	; What we know so far: 
	; * Array contains only 00 and FF. 
	; * Number of 00 bytes.
	ld	A,E
	cp	$3E
	jr	nz,.badvalue
	; * Array contains exactly $3E zeros and 2 FF.
	; * But not yet whether the two FF are contiguous.
	ld	A,[SCRATCH+$3F]
	ld	B,A			; Last value wrapped
	ld	C,$40
	ld	DE,$0000
	ld	HL,SCRATCH

.checkloop
	ld	A,[HL+]
	or	A
	jr	z,.nextvalue
	inc	B			; Check if last value was also FF.
	jr	z,.store_acc
.nextvalue
	ld	B,A			; Save current value as last value.
	dec	C
	jr	nz,.checkloop
	jr	.badvalue		; Iterated through whole array without finding two consecutive FF...
.store_acc
	ld	A,C
	sub	$0B			; Tuned offset
	and	$3f			; Modulo to 0-$3F
	sub	6+3+3+3			; Subtract the time consumed by the code before the read, and the implied call instruction.
	jr	nc,.nocarry
	ld	HL,div_store
	dec	[HL]
.nocarry
	and	$3f			; Modulo to 0-$3F again
.store_acc_raw
	ldh	[div_acc_store],A
	ret
.badvalue
	ld	A,$FF
	jr	.store_acc_raw

; Seeks through a list of null-separated strings to find the string with index A.
; HL=Pointer to a list of consecutive, null-terminated strings.
; A=Index.
GET_STRING_FROM_INDEX:
	ld	E,A
	or	A
.loop
	ret	z
.seeknull
	ld	A,[HL+]
	or	A
	jr	nz,.seeknull
	dec	E
	jr	.loop


SECTION "Util", ROM0
; Simple, slow memcopy.
; HL=Source.
; DE=Destination.
; BC=Length.
COPY:
	ld	A,[HL+]
	ld	[DE],A
	inc	DE
	dec	BC
	ld	A,B
	or	C
	jr	nz,COPY
	ret

; Clears memory in 256 byte chunks up to a page boundary.
; E=Value to clear with.
; HL=Start address.
; B=End address (Exclusive.)
; Example: To clear WRAM:
; E=0 HL=$C000 B=$E0
FASTCLEAR:
	ld	A,E
	;xor	A
	ld	C,64
.loop::
	ld	[HL+],A
	ld	[HL+],A
	ld	[HL+],A
	ld	[HL+],A
	dec	C
	jr	nz,.loop
	ld	A,H
	cp	B
	ret	z
	jr	FASTCLEAR

; Minimal print function
MPRINT:
	ld	A,[HL+]
	or	A
	ret	z
	cp	"\n"
	jr	z,.nextrow
	ld	[DE],A
	inc	DE
	jr	MPRINT
.nextrow
	ld	A,E
	and	$E0
	add	$20
	ld	E,A
	jr	nc,MPRINT
	inc	D
	jr	MPRINT

; Print one hexadecimal byte.
PRINTHEX:
	ld	E,A
	swap	A
	call	PRINTHEX_DIGIT
	ld	A,E
PRINTHEX_DIGIT:
	and	$0F
	add	$30
	cp	$3A
	jr	c,.noupper
	add	7
.noupper
	ld	[HL+],A
	ret

; Library code for SGB transfers and detection.
	include "code/sgb.asm"


SECTION "Graphics", ROM0
Font0:
	incbin "graphics/font0.2bpp"
.end
GbcPals:
	PAL_ENTRY	31,31,31
	PAL_ENTRY	16,16,16
	PAL_ENTRY	8,8,8
	PAL_ENTRY	0,0,0

SECTION "Strings", ROM0
S_ALL:	db "WHICHBOOT.GB V1.1\n"
	db "CPU AF:     BC:\n"
	db "    DE:     HL:\n"
	db "    SP:\n"
	db "TIMING\n"
	db " LY:   DIV:  .\n"
	db "LOGO>             <\n"
	db "    >            <<\n"
	db "HEURISTIC MATCH\n\n"
	db "EXACT CPU REG MATCH\n\n"
	db "TIMING MATCH\n\n"
	db "LOGO MATCH\n"
	db " LOGO:\n"
	db " MAP:\n"
	db " NULL:    R:\n"
	db 0

LOGO_MAP_1:
	db $01,$02,$03,$04,$05,$06,$07,$08,$09,$0A,$0B,$0C,$19
LOGO_MAP_2:
	db $0D,$0E,$0F,$10,$11,$12,$13,$14,$15,$16,$17,$18

SECTION "Reg and timing data", ROM0
REG_REFERENCES:
	; Hardware
	db	$FE,$FF,$03,$84,$C1,$00,$13,$FF,$00,$01	; DMG0
	db	$FE,$FF,$4D,$01,$D8,$00,$13,$00,$B0,$01	; DMG
	db	$FE,$FF,$4D,$01,$D8,$00,$13,$00,$B0,$FF	; GB Pocket
	db	$FE,$FF,$34,$01,$5B,$00,$13,$00,$C0,$01	; Game Fighter
	db	$FE,$FF,$33,$01,$C6,$BA,$14,$00,$B0,$01	; Fortune
	db	$FE,$FF,$60,$C0,$00,$00,$14,$00,$00,$01	; SGB
	db	$FE,$FF,$60,$C0,$00,$00,$14,$00,$00,$FF	; SGB2
	db	$FE,$FF,$0D,$00,$56,$FF,$00,$00,$80,$11	; GBC
	db	$FE,$FF,$0D,$00,$56,$FF,$00,$01,$00,$11 ; GBA

	; Emulators
	db	$FE,$FF,$4D,$01,$D8,$00,$00,$00,$B0,$11	; KiGB GBC mode
	db	$FE,$FF,$4D,$01,$D8,$00,$00,$01,$B0,$11	; KiGB GBA mode
	db	$FE,$FF,$4D,$01,$D8,$00,$13,$00,$B0,$11	; HGB/GB Online/BinjGB
	db	$FE,$FF,$0D,$00,$56,$FF,$00,$00,$B0,$11	; VBA GBC
	db	$FE,$FF,$0D,$00,$56,$FF,$00,$01,$B0,$11	; VBA GBA
	db	$FE,$FF,$00,$00,$D8,$00,$13,$00,$00,$01	; VBA GBA
	db	$FE,$FF,$87,$00,$8F,$00,$00,$00,$D0,$11	; PyBoy 1.5.1 GBC
	db	$FE,$FF,$87,$00,$8F,$00,$00,$00,$D0,$01	; PyBoy 1.5.1 DMG

.end

PLATFORM_EXACT_NAMES:
; Hardware
S_DMG0:	db	"DMG0",0
S_DMG:	db	"DMG",0
S_GPB:	db	"GBP",0
S_GF:	db	"GAME FIGHTER(CLONE)",0
S_FORTUNE:db	"FORTUNE(CLONE)",0
S_SGB:	db	"SGB",0
S_SGB2:	db	"SGB2",0
S_GBC:	db	"GBC",0
S_GBA:	db	"GBA",0

; Emulators
S_KIGB_GBC:	db	"KIGB GBC MODE",0
S_KIGB_GBA:	db	"KIGB GBA MODE",0
S_HGB:	db	"DMG BUT WITH A=$11",0
S_VBA_GBC:	db	"VBA GBC MODE",0
S_VBA_GBA:	db	"VBA GBA MODE",0
	db	"JSGB BY IMRAN NAZAR",0
S_PYBOY_GBC:	db	"PYBOY GBC MODE",0
S_PYBOY_DMG:	db	"PYBOY DMG MODE",0


S_UNK:	db	"NO EXACT MATCH",0

TIMING_REFERENCES:
	; Hardware
	db	$91,$18,$0D	; DMG0
	db	$00,$AB,$34	; DMG/GBP
	db	$03,$87,$0A	; Game Fighter
	db	$94,$B1,$0D	; Fortune
	db	$90,$20,$2B	; GBC0
	db	$90,$1E,$28	; GBC
	db	$90,$1E,$29	; GBA
	; Emulators
	db	$00,$00,$00	; VBA/HHUGBOY DMG
	db	$00,$AF,$00	; KiGB
	db	$00,$EB,$19	; KiGB with DMG boot ROM
	db	$91,$00,$00	; VBA/HHUGBOY GBC

	db	$00,$AC,$17	; NO$GMB DMG
	db	$90,$1F,$04	; NO$GMB GBC

	db	$92,$AC,$09	; SAMEBOOT 0.15 GBC
	db	$92,$AC,$0B	; SAMEBOOT 0.15 GBA
	db	$90,$BD,$07	; SAMEBOOT DMG
	db	$11,$45,$22	; SAMEBOOT SGB
	db	$92,$AA,$15	; SAMEBOOT 0.15 GBC0

	db	$00,$27,$31	; SAMEBOOT 0.13 GBC

	db	$00,$00,$FF	; Timer error (HGB/Rew/JSGB by Imran)
	db	$00,$92,$07	; Emulicious 2022-07-22

	db	$00,$69,$29	; Gameboy Online

	db	$00,$AC,$02	; BinjGB
	db	$90,$AB,$34	; WasmBoy DMG mode (And VaporBoy is just WasmBoy?)
	db	$00,$FF,$3C	; JSGB Pedro Ladaria
	db	$00,$1A,$12	; Emulicious (DMG, no boot ROM)
	db	$00,$00,$03	; No boot ROM.
	db	$00,$AB,$2C	; Ares DMG.
	db	$90,$22,$28	; Ares GBC.
	db	$00,$AB,$35	; DMG/GBP+1 M cycle
	db	$91,$82,$29	; PyBoy 1.5.1
	db	$99,$F3,$31	; PyBoy 1.5.1 with DMG boot ROM
	db	$90,$28,$37	; PyBoy 1.5.1 with GBC boot ROM


;	db	$00,$D9,$01-08	; SGB/SGB2 (detected manually because it's a range)
.end


VRAM_LOGO_NINTENDO:
	incbin "vram_logo_nintendo.bin"
VRAM_LOGO_LOADING:
	incbin "vram_logo_loading.bin"
VRAM_COPYRIGHT:
	incbin "vram_copyright.bin"

S_NO:	db	"NO",0
S_YES:	db	"YES",0
S_BAD:	db	"UNK",0
S_OK:	db	"OK",0

PLATFORM_VRAM_NAMES:
S_VPLAT_NONE:db		"LOGO:NONE(EMU/CLONE)",0
S_VPLAT_NINTENDO:db	" LOGO:NINTENDO",0
S_VPLAT_LOADING:db	" LOGO:MAXSTATION",0
S_VPLAT_UNK:db		" LOGO:UNKNOWN",0

PLATFORM_VRAM_MAP_NAMES:
S_VMPLAT_NONE:db	"NO(GBC/EMU/CLN)",0
S_VMPLAT_YES_R:db	"YES(WITH R)",0
S_VMPLAT_YES:db		"YES(NO R)",0
S_VMPLAT_UNK:db		"UNKNOWN",0

PLATFORM_VRAM_R_NAMES:
S_VRPLAT_NONE:db	"MISSING",0
S_VRPLAT_YES:db		"YES",0
S_VRPLAT_UNK:db		"UNKNOWN",0

PLATFORM_TIMING_NAMES:
; Hardware
S_DMG0_T:db	"DMG0",0
S_DMG_T:db	"DMG/GBP",0
S_GF_T:	db	"GAME FIGHTER(CLONE)",0
S_FORTUNE_T:db	"FORTUNE(CLONE)",0
S_GBC0_T:db	"GBC0",0
S_GBC_T:db	"GBC",0
S_GBA_T:db	"GBA",0

; Emulators
	db	"VBA/HHUGBOY DMG",0
	db	"KIGB",0
	db	"KIGB(WITH DMG BOOT ROM)",0
	db	"VBA/HHUGBOY GBC",0
	db	"NO$GMB DMG/GBP/SGB",0
	db	"NO$GMB GBC",0

	db	"SAMEBOOT 0.15 GBC",0
	db	"SAMEBOOT 0.15 GBA",0
	db	"SAMEBOOT DMG/GBP",0
	db	"SAMEBOOT SGB",0
	db	"SAMEBOOT 0.15 GBC0",0

	db	"SAMEBOOT 0.13 GBC",0
	db	"HGB/REW ETC",0

	db	"EMULICIOUS",0

	db	"GAMEBOY ONLINE",0
	db	"BINJGB",0
	db	"WASMBOY DMG MODE",0

	db	"JSGB BY PEDRO\n LADARIA",0
	db	"EMULICIOUS \n (DMG NO BOOT ROM)",0
	db	"NO BOOT ROM",0

	db	"ARES DMG",0
	db	"ARES GBC",0

	db	"DMG+1 M CYCLE",0

	db	"PYBOY",0
	db	"PYBOY+DMG BOOT ROM",0
	db	"PYBOY+GBC BOOT ROM",0


S_UNK_T:db	"NO EXACT MATCH",0
S_SGB_T:db	"SGB/SGB2(FUZZY)",0


PLATFORM_HEUR_NAMES:
S_DMG_H:	db	"DMG",0
S_GPB_H:	db	"GBP",0
S_GBC_H:	db	"GBC",0
S_GBA_H:	db	"GBA",0
S_SGB_H:	db	"SGB",0
S_SGB2_H:	db	"SGB2",0
S_SGB_GBC_H:	db	"SGB+GBC",0
S_SGB_GBA_H:	db	"SGB+GBA",0

S_INVALID:	db	"INVALID VALUE!",0
S_ERROR:	db	"ERROR!",0
S_START0:	db	"ENTRY POINT 0",0

SECTION "Vars", HRAM
platform_heur:	DB
platform_exact:	DB
platform_timing:DB
platform_vram:DB
platform_start0:DB
ly_store:	DB
div_store:	DB
div_acc_store:	DB
temp1:	DB
temp2:	DB
temp3:	DB

SECTION "Reg storage", HRAM[$FFC0]
RegStorage:
.sp	DS	2
.hl
.l	DB
.h	DB
.de
.e	DB
.d	DB
.bc
.c	DB
.b	DB
.af
.f	DB
.a	DB
.top

SECTION "Fine calc scratch", WRAM0
; Buffer for capturing timing data.
SCRATCH:
	ds	$40

SECTION "Stack", HRAM[$FFE1]
Stack:
	ds	$0e
.top