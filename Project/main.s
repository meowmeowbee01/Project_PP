.segment "HEADER"
	INES_MAPPER = 0				; 0 = NROM
	INES_MIRROR = 0				; 0 = horizontal mirroring, 1 = vertical mirroring
	INES_SRAM   = 0				; 1 = battery backed SRAM at $6000-7FFF

	.byte "NES", $1a			; iNES header identifier
	.byte $02					; 2x 16KB PRG code
	.byte $01					; 1x  8KB CHR data
	.byte INES_MIRROR | (INES_SRAM << 1) | ((INES_MAPPER & $f) << $4)
	.byte (INES_MAPPER & %11110000)
	.byte 0, 0, 0, 0, 0, 0, 0, 0	; padding

.segment "VECTORS"
	.addr nmi		; when an NMI happens (once per frame if enabled), a jump to the label nmi will occur
	.addr reset		; when the processor first turns on or is reset, a jump to the label reset will occur
	.addr irq		; when an external interrupt is requested and IRQs are enabled, a jump to the irq label will occur

.segment "STARTUP"	; "nes" linker config requires a STARTUP section, even if it's empty

.segment "TILES"	; character memory
	.incbin "PP.chr"

.segment "ZEROPAGE"

.segment "OAM"
	oam: .res $ff

.include "neslib.s"

.segment "CODE"		; main code segment for the program
	hello_world:
	.byte "HELLO WORLD",0

	.proc irq
		rti ; do nothing if an IRQ happens
	.endproc

	.proc reset
		sei					; disable IRQs
		cld					; disable decimal mode
		lda #0
		sta PPU_CONTROL		; disable NMI
		sta PPU_MASK 		; disable rendering
		sta APU_DM_CONTROL	; disable DMC IRQs
		lda #$40			
		sta $4017			; disable APU frame IRQ
		ldx #$ff 			; Set up stack
		tsx 

		@vblankwait1:		; first wait for vblank to make sure PPU is ready
			bit PPU_STATUS
			bpl @vblankwait1

		lda #0				; value we write in each register -> A
		ldx #0				; loop counter -> X
		@clear_memory:		; 8 blocks of memory X 256 = 2K cleared
			sta 0, x			; store whatever a has in given address with offset in X
			sta $0100, x
			sta $0200, x
			sta $0300, x
			sta $0400, x
			sta $0500, x
			sta $0600, x
			sta $0700, x
			inx 
			bne @clear_memory 	; loop will stop when X goes back to 0

		; maybe add a clear_oam here ???

		@vblankwait2:	; second wait for vblank, PPU is ready after this
			bit PPU_STATUS
			bpl @vblankwait2

		lda #%10001000
  		sta PPU_CONTROL ; enable nmi

		jmp main
	.endproc

	.proc nmi
		save_registers

		ldx #0			; set SPR-RAM address to 0
		stx PPU_SPRRAM_ADDRESS

		@loop:
			lda hello, x 		; load the hello message into SPR-RAM
			sta PPU_SPRRAM_IO
			inx 
			cpx #$28
			bne @loop

		restore_regsiters
		rti 
	.endproc

	.proc main ; main application - rendering is currently off
		load_palettes:
			lda #$3f 		; Set PPU address to $3F
			sta PPU_VRAM_ADDRESS2
			lda #0
			sta PPU_VRAM_ADDRESS2
		
		ldx #0
		@loop:				; Loop transfers 32 (20hex) bytes of palette data to VRAM
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

	hello:
		.byte 0, 0, 0, 0	; why do I need these here?
		.byte 0, 0, 0, 0

		.byte $6c, 'P', 0, $60
		.byte $6c, 'E', 0, $68
		.byte $6c, 'E', 0, $70
		.byte $6c, 'E', 0, $78
		.byte $6c, 'P', 0, $80
		.byte $6c, 'E', 0, $88
		.byte $6c, 'E', 0, $90
		.byte $6c, 'E', 0, $98

	palettes:
		.byte $0f, 0, 0, 0	; background palette
		.byte $0f, 0, 0, 0
		.byte $0f, 0, 0, 0
		.byte $0f, 0, 0, 0

		.byte $0f, $26, 0, 0	; sprite palette
		.byte $0f, 0, 0, 0
		.byte $0f, 0, 0, 0
		.byte $0f, 0, 0, 0