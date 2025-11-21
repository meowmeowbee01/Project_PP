.segment "HEADER"
	INES_MAPPER = 0				; 0 = NROM
	INES_MIRROR = 1				; 0 = horizontal mirroring, 1 = vertical mirroring
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

.segment "TILES"
	.incbin "PP.chr"

.segment "ZEROPAGE"
	paddr: .res 2 	; pointer to 16 bit address

.segment "OAM"
	oam: .res $100

.include "neslib.s"

.segment "BSS"
	palette: .res $20

.segment "CODE" 	; main code segment for the program
	text:
		.byte "Hello", $a
		.byte "World__", $c

		.byte "new", $a
		.byte "page", 0
	title_attributes: .byte %11110000,%11111111,%11111111,%11111111,%11111111,%11111111,%11111111,%11111111

	.proc irq
		rti 		; do nothing if an IRQ happens
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
		ldx #$ff
		tsx 				; Set up stack pointer

		@vblankwait1:		; first wait for vblank to make sure PPU is ready
			bit PPU_STATUS
			bpl @vblankwait1

		lda #0				; value we write in each register -> A
		ldx #0				; loop counter -> X
		@clear_memory:		; 8 blocks of memory X 256 = 2K cleared
			sta 0, x		; store whatever a has in given address with offset in X
			sta $0100, x
			sta $0200, x
			sta $0300, x
			sta $0400, x
			sta $0500, x
			sta $0600, x
			sta $0700, x
			inx 
			bne @clear_memory 	; loop will stop when X goes back to 0

		jsr clear_sprites 		; clear oam (sprites)

		@vblankwait2:	; second wait for vblank, PPU is ready after this
			bit PPU_STATUS
			bpl @vblankwait2

		lda #%10001000
  		sta PPU_CONTROL ; enable nmi

		ldx #0 			; initialize palette table
		@paletteloop:
			lda default_palette, x
			sta palette, x
			inx 
			cpx #$20
			bcc @paletteloop

		jsr ppu_off 			; turn rendering off
		clear_nametable(NAME_TABLE_0_ADDRESS)
		clear_nametable(NAME_TABLE_1_ADDRESS)

		assign_16i text_address, text 			; make the text_address pointer point to text
		jsr write_text							; write the text that's in text_address

		vram_set_address (ATTRIBUTE_TABLE_0_ADDRESS + 4 * 8 + 1) 		; sets the title text to use the second palette
		assign_16i paddr, title_attributes

		ldy #0
		@loop: 				; write all attributes to the vram
			lda (paddr),y
			sta PPU_VRAM_IO
			iny 
			cpy #2
			bne @loop

		lda #VBLANK_NMI|BG_0000|OBJ_1000 ; set our game settings
		sta ppu_ctl0
		lda #BG_ON|OBJ_ON
		sta ppu_ctl1

		jsr ppu_update

		jmp mainloop
	.endproc

	.proc nmi
		save_registers

		; transfer current palette to PPU
		vram_set_address $3f00
		ldx #0 ; transfer the 32 bytes to VRAM
		@loop:
			lda palette, x
			sta PPU_VRAM_IO
			inx 
			cpx #$20
			bcc @loop

		; write current scroll and control settings
		lda #0
		sta PPU_VRAM_ADDRESS1
		sta PPU_VRAM_ADDRESS1
		lda ppu_ctl0
		sta PPU_CONTROL
		lda ppu_ctl1
		sta PPU_MASK

		; flag PPU update complete
		ldx #0
		stx nmi_ready

		restore_regsiters
		rti 
	.endproc

	.proc mainloop
		jmp mainloop
	.endproc

.segment "RODATA"
	default_palette: 	; background palette
		.byte $0f, $15, $16, $26 ; red
		.byte $0f, $1a, $2a, $29 ; green
		.byte $0f, $11, $21, $2c ; blue
		.byte $0f, $30, $10, $00 ; gray
						; sprite palette
		.byte $0f, $28, $21, $11
		.byte $0f, $26, $28, $17
		.byte $0f, $1b, $2b, $3b
		.byte $0f, $12, $22, $32