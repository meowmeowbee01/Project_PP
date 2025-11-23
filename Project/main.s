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
	text_line: .res 1
	slide: .res 1
	remaining_input_cooldown: .res 1

.segment "OAM"
	oam: .res $100

.include "neslib.s"

.segment "BSS"
	palette: .res $20

.segment "CODE" 	; main code segment for the program
	INPUT_COOLDOWN = 60 	; frames

	text:
		.incbin "content.ascii" 			; $a == 10 == newline, $c == 12 == new page, 0 == end of data
		.byte $c

		.byte "hello", $a
		.byte "world", $c

		.byte "new", $a
		.byte "page", $c

		.byte "BOOM!", $a
		.byte "third", $a
		.byte "page", $c

		.byte "that's right:", $a
		.byte "fourth page", $c

		.byte "final", $a
		.byte "page", $c

		.byte "PSYCHED:", $a
		.byte "another page", $c

		.byte "okay,", $a
		.byte "ACTUAL", $a
		.byte "final", $a
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
		jsr prepare_slide							; write the text that's in text_address

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

		lda #0
		cmp remaining_input_cooldown
		beq skip_decrement
			dec remaining_input_cooldown
		skip_decrement:

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
		sta PPU_SCROLL
		sta PPU_SCROLL
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
		lda remaining_input_cooldown 	; keep looping till remaining input cooldown is 0
		bne mainloop
		jsr gamepad_poll 				; keep looping till a is pressed or gun is triggered
		lda gamepad
		and #PAD_A
		bne next_slide
		lda GUN_TRIGGER
		beq mainloop
		next_slide:
			lda #INPUT_COOLDOWN 			; set remaining input cooldown
			sta remaining_input_cooldown
			jsr ppu_off
			clear_nametable(NAME_TABLE_0_ADDRESS)
			inc slide 						; increment slide
			jsr prepare_slide
			jsr ppu_update
			jmp mainloop
	.endproc

	.proc prepare_slide
		vram_set_address (NAME_TABLE_0_ADDRESS) 	; set the vram address
		ldy #0
		sty text_line
		ldx #0
		find_slide_loop: 			; set y to the beginning of the current slide
			txa 					; check difference between slide and x
			cmp slide
			beq loop 				; proceed to main loop if they are equal
			lda (text_address),y 	; get current text byte (2 bytes address)
			beq exit 				; if it's 0, exit
			iny 
			cmp #$c
			bne skip_slide_increment
				inx 
			skip_slide_increment:
			jmp find_slide_loop
		loop:
			lda (text_address),y 	; get current text byte (2 bytes address)
			beq exit 				; if it's 0, exit
			cmp #$c 				; if it's the end of the slide, exit
			beq exit
			cmp #$a					; if its $a go to a new line ($a == 10 == newline on the ascii table)
			bne skip_newline
				inc text_line 
				lda PPU_STATUS 		; load ppu status
				lda #>NAME_TABLE_0_ADDRESS
				sta PPU_VRAM_ADDRESS 
				lda text_line
				asl 
				asl 
				asl 
				asl 
				asl 
				clc 
				adc #<NAME_TABLE_0_ADDRESS
				sta PPU_VRAM_ADDRESS
				jmp skip_write
			skip_newline:
				sta PPU_VRAM_IO 	; write it to the ppu io register
			skip_write:
			iny 					; increment y
			jmp loop 				; loop again
		exit:
			rts 					; return from subroutine
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