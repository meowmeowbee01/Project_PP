; PPU registers
PPU_CONTROL			= $2000		; PPU control register 1 (write)
PPU_MASK			= $2001		; PPU control register 2 (write)
PPU_STATUS			= $2002		; PPU status register (read)
PPU_SPRRAM_ADDRESS	= $2003 	; PPU SPR-RAM address register (write)
PPU_SPRRAM_IO		= $2004 	; PPU SPR-RAM I/O register (write)
PPU_VRAM_ADDRESS1	= $2005 	; PPU VRAM address register 1 (write)
PPU_VRAM_ADDRESS2	= $2006 	; PPU VRAM address register 2 (write)
PPU_VRAM_IO			= $2007 	; VRAM I/O register (read/write)
SPRITE_DMA			= $4014 	; sprite DMA register

; APU registers
APU_DM_CONTROL		= $4010		; APU delta modulation control register (write)
APU_CLOCK			= $4015		; APU sound/vertical clock signal register (read/write)

; joystick/controller values
JOYPAD1 = $4016		; joypad 1 (read/write)
JOYPAD2 = $4017		; joypad 2 (read/write)

; gamepad bit values
PAD_A		= %00000001
PAD_B		= %00000010
PAD_SELECT	= %00000100
PAD_START	= %00001000
PAD_UP		= %00010000
PAD_DOWN	= %00100000
PAD_LEFT	= %01000000
PAD_RIGHT	= %10000000

.segment "OAM"
.segment "HEADER"
	INES_MAPPER = 0				; 0 = NROM
	INES_MIRROR = 0				; 0 = horizontal mirroring, 1 = vertical mirroring
	INES_SRAM   = 0				; 1 = battery backed SRAM at $6000-7FFF

	.byte "NES", $1a			; iNES header identifier
	.byte $02					; 2x 16KB PRG code
	.byte $01					; 1x  8KB CHR data
	.byte INES_MIRROR | (INES_SRAM << 1) | ((INES_MAPPER & $f) << 4)
	.byte (INES_MAPPER & %11110000)
	.byte $0, $0, $0, $0, $0, $0, $0, $0	; padding

.segment "VECTORS"
	.addr nmi		; when an NMI happens (once per frame if enabled), a jump to the label nmi will occur
	.addr reset		; when the processor first turns on or is reset, a jump to the label reset will occur
	.addr irq		; when an external interrupt is requested and IRQs are enabled, a jump to the irq label will occur

.segment "STARTUP"	; "nes" linker config requires a STARTUP section, even if it's empty


.segment "CODE"		; main code segment for the program

	irq:
		rti				; do nothing if an IRQ happens

	.proc reset:
		sei					; disable IRQs
		cld					; disable decimal mode
		ldx #0
		stx PPU_CONTROL		; disable NMI
		stx PPU_MASK 		; disable rendering
		stx APU_DM_CONTROL	; disable DMC IRQs
		ldx #$40			
		stx $4017			; disable APU frame IRQ
		ldx #$ff 			; Set up stack
		txs 

		vblankwait1:	; first wait for vblank to make sure PPU is ready
			bit PPU_STATUS
			bpl vblankwait1

		lda #0				; value we write in each register -> A
		ldx #0				; loop counter -> X
		clear_memory:		; 8 blocks of memory X 256 = 2K cleared
			sta $00, x			; store whatever a has in given address with offset in X
			sta $0100, x
			sta $0200, x
			sta $0300, x
			sta $0400, x
			sta $0500, x
			sta $0600, x
			sta $0700, x
			inx 
			bne clear_memory 	; loop will stop when X goes back to 0

		; maybe add a clear_oam here ???

		vblankwait2:	; second wait for vblank, PPU is ready after this
			bit PPU_STATUS
			bpl vblankwait2

		lda #%10001000
  		sta PPU_CONTROL ;enable nmi

		jmp main
	.endproc

	.proc main:
	; main application - rendering is currently off
		load_palettes:
			lda #$3f 				; Set PPU address to $3F
			sta PPU_VRAM_ADDRESS2
			lda #0
			sta PPU_VRAM_ADDRESS2
		
		ldx #0
		@loop:						; Loop transfers 32 (20hex) bytes of palette data to VRAM
			lda palettes, x
			sta PPU_VRAM_IO
			inx 
			cpx #$20
			bne @loop

		enable_rendering:
			lda #%10000000	; enable NMI
			sta PPU_CONTROL
			lda #%00010000	; enable Sprites
			sta PPU_MASK

		forever:
			jmp forever
	.endproc

	.proc nmi:
		; save registers
		pha
		txa
		pha
		tya
		pha

		ldx #$00			; set SPR-RAM address to 0
		stx PPU_SPRRAM_ADDRESS

		@loop:
			lda hello, x 		; load the hello message into SPR-RAM
			sta PPU_SPRRAM_IO
			inx 
			cpx #$28
			bne @loop
			rti 

		; flag PPU update complete
		ldx #0
		stx nmi_ready

		; restore registers and return
		pla
		tay
		pla
		tax
		pla
		rti
	.endproc

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

.segment "TILES"	; character memory
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