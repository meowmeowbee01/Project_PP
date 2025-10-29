.segment "HEADER"
	;.byte "NES", $1a			; iNES header identifier
	.byte $4e, $45, $53, $1a
	.byte 2 					; 2x 16KB PRG code
	.byte 1						; 1x  8KB CHR data
	.byte $01, $00				; mapper 0, vertical mirroring

.segment "VECTORS"
	.addr nmi		; when an NMI happens (once per frame if enabled) the label nmi
	.addr reset		; when the processor first turns on or is reset, it will jump to the label reset
	.addr 0			; external interrupt IRQ (unused)

.segment "STARTUP"		; "nes" linker config requires a STARTUP section, even if it's empty

.segment "CODE"			; main code segment for the program

reset:
	sei			; disable IRQs
	cld			; disable decimal mode
	ldx #$40
	stx $4017	; disable APU frame IRQ
	ldx #$ff 	; Set up stack
	txs			
	inx			; now X = 0
	stx $2000	; disable NMI
	stx $2001 	; disable rendering
	stx $4010 	; disable DMC IRQs

vblankwait1:	; first wait for vblank to make sure PPU is ready
	bit $2002
	bpl vblankwait1

clear_memory:
  lda #$00
  sta $0000, x
  sta $0100, x
  sta $0200, x
  sta $0300, x
  sta $0400, x
  sta $0500, x
  sta $0600, x
  sta $0700, x
  inx
  bne clear_memory

vblankwait2:	; second wait for vblank, PPU is ready after this
	bit $2002
	bpl vblankwait2

main:
load_palettes:
	lda $2002
	lda #$3f
	sta $2006
	lda #$00
	sta $2006
	ldx #$00

@loop:
	lda palettes, x
	sta $2007
	inx
	cpx #$20
	bne @loop

enable_rendering:
	lda #%10000000	; enable NMI
	sta $2000
	lda #%00010000	; enable Sprites
	sta $2001

forever:
	jmp forever

nmi:
	ldx #$00			; set SPR-RAM address to 0
	stx $2003
@loop:	lda hello, x 	; load the hello message into SPR-RAM
	sta $2004
	inx
	cpx #$28			; stupid to choose 92 since there's only 40 bytes possible a typo
	bne @loop
	rti

hello:
	.byte $00, $00, $00, $00	; why do I need these here?
	.byte $00, $00, $00, $00

	.byte $6c, $03, $00, $4e	;h 
	.byte $6c, $04, $00, $58	;e
	.byte $6c, $05, $00, $62	;l
	.byte $6c, $05, $00, $6c	;l
	.byte $6c, $01, $00, $76	;o
	.byte $6c, $00, $00, $8a	;t
	.byte $6c, $01, $00, $94	;o
	.byte $6c, $02, $00, $9e	;m



palettes:
	.byte $0f, $00, $00, $00	; background palette
	.byte $0f, $00, $00, $00
	.byte $0f, $00, $00, $00
	.byte $0f, $00, $00, $00

	.byte $0f, $26, $00, $00	; sprite palette
	.byte $0f, $00, $00, $00
	.byte $0f, $00, $00, $00
	.byte $0f, $00, $00, $00

.segment "CHARS"	; character memory
	.byte %11111111	; T (00)
	.byte %11111111
	.byte %00011000
	.byte %00011000
	.byte %00011000
	.byte %00011000
	.byte %00011000
	.byte %00011000
	.byte $00, $00, $00, $00, $00, $00, $00, $00

	.byte %11111111 ; O (01)
	.byte %11111111
	.byte %11000011
	.byte %11000011
	.byte %11000011
	.byte %11000011
	.byte %11111111
	.byte %11111111
	.byte $00, $00, $00, $00, $00, $00, $00, $00

	.byte %11000011	; M (02)
	.byte %11100111
	.byte %11111111
	.byte %11011011
	.byte %11000011
	.byte %11000011
	.byte %11000011
	.byte %11000011
	.byte $00, $00, $00, $00, $00, $00, $00, $00

	.byte %11000011	; H (03)
	.byte %11000011
	.byte %11000011
	.byte %11111111
	.byte %11111111
	.byte %11000011
	.byte %11000011
	.byte %11000011
	.byte $00, $00, $00, $00, $00, $00, $00, $00

	.byte %11111111	; E (04)
	.byte %11111111
	.byte %11000000
	.byte %11111100
	.byte %11111100
	.byte %11000000
	.byte %11111111
	.byte %11111111
	.byte $00, $00, $00, $00, $00, $00, $00, $00

	.byte %11000000	; L (05)
	.byte %11000000
	.byte %11000000
	.byte %11000000
	.byte %11000000
	.byte %11000000
	.byte %11111111
	.byte %11111111
	.byte $00, $00, $00, $00, $00, $00, $00, $00  