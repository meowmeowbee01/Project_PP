.include "neslib.s"
NEWLINE = $a
CARRIAGE_RETURN = $d
TAB = '	'
SPACE = ' '
MAX_HEIGHT = $1e

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
	current_palette: .res 1
	character_pointer: .res 2 		; points to start of slide
	character_pointer_next: .res 2 	; points to start of next slide
	number_of_slides: .res 1
	scroll_x: .res 1				; scroll offset
	temp_ones: .res 1
	temp: .res 1

.segment "OAM"
	oam: .res $100

.segment "BSS"
	palette: .res $20

.segment "CODE" 	; main code segment for the program
	.include "settings.s"
	SLIDE_INDEX_ADDR0 = NAME_TABLE_0_ADDRESS + (INDEX_Y_POS * $20) + INDEX_X_POS
	SLIDE_INDEX_ADDR1 = NAME_TABLE_1_ADDRESS + (INDEX_Y_POS * $20) + INDEX_X_POS
	MAX_WIDTH = $20 - PADDING_RIGHT
	text:
		.incbin "content.txt"
		.byte 0

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
			sta $0300, x
			sta $0400, x
			sta $0500, x
			sta $0600, x
			sta $0700, x
			lda #$ff
			sta $0200, x
			lda #0
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

		jsr setup_first_slide
		jsr set_number_of_slides
		jsr display_current_slide
		jsr prepare_next_slide_nametable

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
		lda scroll_x
		sta PPU_SCROLL
		lda #0
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
		jsr gamepad_poll 				; keep looping till there is an input
		lda gamepad
		and #PAD_A|PAD_RIGHT
		bne next_slide
		lda gamepad
		and #PAD_B|PAD_LEFT
		bne prev_slide
		lda JOYPAD2
		and #GUN_TRIGGER
		bne next_slide
		jmp mainloop
		next_slide:
			lda #INPUT_COOLDOWN 			; set remaining input cooldown
			sta remaining_input_cooldown
			jsr scroll_next
			jsr ppu_off
			clear_nametable(NAME_TABLE_0_ADDRESS)
			clear_nametable(NAME_TABLE_1_ADDRESS)
			jsr go_to_next_slide
			jsr display_current_slide
			jsr prepare_next_slide_nametable
			jsr ppu_update
			jmp mainloop
		prev_slide:
			lda #INPUT_COOLDOWN 			; set remaining input cooldown
			sta remaining_input_cooldown
			jsr ppu_off
			clear_nametable(NAME_TABLE_0_ADDRESS)
			clear_nametable(NAME_TABLE_1_ADDRESS)
			jsr go_to_previous_slide
			jsr display_current_slide
			lda #$ff ; screen width
			sta scroll_x
			jsr prepare_next_slide_nametable
			jsr ppu_update
			jsr scroll_next
			jmp mainloop
	.endproc

	.proc set_number_of_slides
		ldx #1
		loop:
			increment_16i_pointer character_pointer
			ldy #0
			lda (character_pointer), y 	; y is 0 so just the character the pointer points to
			beq exit 					; if it's 0, we're past the last slide
			cmp #ESCAPE_CHAR
			bne loop
				ldy #1
				lda (character_pointer), y 		; check the next character
				cmp #SLIDE_SEPERATOR
				bne loop
				inx 
				jmp loop
		exit:
			assign_16i character_pointer, text	; set current slide pointer to the first slide
			stx number_of_slides 
			rts 
	.endproc

	.proc set_padding
		ldx #0
		loop:
			cpx #PADDING_TOP
			beq exit
			inx 
			jmp loop
		exit:
		stx text_line
		rts 
	.endproc

	.proc setup_first_slide
		lda #0
		sta slide
		assign_16i character_pointer, text
		jsr set_padding
		jsr set_attributes
		rts 
	.endproc

	.proc scroll_next
		lda scroll_x
		beq forward
		back_loop:
			sta scroll_x	
			tay 
			jsr ppu_update	; wait nmi
			lda remaining_input_cooldown
			bne skip_input_backwards
				jsr gamepad_poll
				lda gamepad
				and #PAD_A|PAD_RIGHT|PAD_B|PAD_LEFT
				bne skipped
			skip_input_backwards:
			tya 
			clc 
			cmp #SCROLL_SPEED 		; end transition when left side reached
			bcc done
			sec 
			sbc #SCROLL_SPEED
			jmp back_loop
		forward:
		lda #0
		forward_loop:
			sta scroll_x
			tay 
			jsr ppu_update 	; wait nmi
			lda remaining_input_cooldown
			bne skip_input_forward
				jsr gamepad_poll
				lda gamepad
				and #PAD_A|PAD_RIGHT|PAD_B|PAD_LEFT
				bne skipped
			skip_input_forward:
			tya 
			clc 
			adc #SCROLL_SPEED
			bcs done
			jmp forward_loop
		skipped:
			lda #INPUT_COOLDOWN
			sta remaining_input_cooldown
		done:
			lda #0
			sta scroll_x
			rts 
	.endproc

	.proc go_to_next_slide
		jsr set_padding
		ldx #0
		ldy #0
		jmp skip_increment 				; character_pointer points at the end of previous slide so don't increment the first time
		find_next_slide: 	 			; proceed if they are equal
			increment_16i_pointer character_pointer
			skip_increment:
			lda (character_pointer), y 	; y is 0 so just the character the pointer points to
			beq reset_slides 			; if it's 0, go back to first slide since there's a 0 after the content
			cmp #ESCAPE_CHAR
			bne find_next_slide
				ldy #1
				lda (character_pointer), y 		; check the next character
				ldy #0
				cmp #SLIDE_SEPERATOR
				bne find_next_slide
		
		increment_16i_pointer character_pointer 	; skip over \
		increment_16i_pointer character_pointer 	; skip over s
		lda (character_pointer), y
		cmp #CARRIAGE_RETURN
		bne skip_CR_skip
			increment_16i_pointer character_pointer ; skip over CR
		skip_CR_skip:
		increment_16i_pointer character_pointer 	; skip over newline
		inc slide
		jmp attributes

		reset_slides:
			assign_16i character_pointer, text	; set current slide pointer to the first slide
			lda #0
			sta slide
		
		attributes:
			jsr set_attributes

		exit:
			rts 
	.endproc

	.proc go_to_previous_slide
		lda slide
		cmp #0							; if this is the first slide, loop all the way to the end
		bne not_first_slide				; skip if slide index != 0
			ldy #1							; y will serve as slide index
			slide_loop1:					; loop to reach last slide:
				save_registers					
				jsr go_to_next_slide			
				restore_regsiters
				iny 						; since we are on the next slide, inc y
				cpy number_of_slides		; compare to total amount of slides
				bne slide_loop1				; not end? go back
				jmp exit					; is end -> exit
		not_first_slide:
		save_registers
		jsr setup_first_slide
		restore_regsiters
		sec 
		sbc #1
		slide_loop2:
			cmp #0
			beq exit
			pha 
			jsr go_to_next_slide
			pla 
			sec 
			sbc #1
			jmp slide_loop2
		exit:
			rts 
	.endproc

	.proc find_next_slide_start
		ldy #0
		lda (character_pointer), y
		beq reset_slides

		lda character_pointer
		sta character_pointer_next
		lda character_pointer + 1
		sta character_pointer_next + 1
		
		ldx #0
		jmp skip_increment 							; character_pointer points at the end of previous slide so don't increment the first time
		find_next_slide: 							; proceed if they are equal
			increment_16i_pointer character_pointer_next
			skip_increment:
			lda (character_pointer_next), y 		; y is 0 so just the character the pointer points to
			beq reset_slides 						; if it's 0, go back to first slide since there's a 0 after the content
			cmp #ESCAPE_CHAR
			bne find_next_slide
				ldy #1
				lda (character_pointer_next), y 	; check the next character
				ldy #0
				cmp #SLIDE_SEPERATOR
				bne find_next_slide

		increment_16i_pointer character_pointer_next 	; skip over \
		increment_16i_pointer character_pointer_next 	; skip over s
		lda (character_pointer_next), y
		cmp #CARRIAGE_RETURN
		bne skip_CR_skip
			increment_16i_pointer character_pointer_next 	; skip over CR
		skip_CR_skip:
		increment_16i_pointer character_pointer_next 		; skip over newline
		jmp exit

		reset_slides:
			assign_16i character_pointer_next, text 		; set current slide pointer to the first slide

		exit:
			rts 
	.endproc

	.proc prepare_next_slide_nametable
		jsr find_next_slide_start
		jsr set_padding
		jsr set_attributes_next
		jsr display_next_slide_nt1
		rts 
	.endproc

	.proc display_current_slide
		ldy #0
		text_loop:
			lda (character_pointer),y 	; get current text byte (2 bytes address)
			beq exit 					; if it's 0, exit
			cmp #TAB
			bne skip_tab
				jsr write_tab
				jmp skip_write
			skip_tab:
			cmp #NEWLINE 			; check if it's a newline character
			bne skip_newline 		; if it isn't, branch
			force_newline:
				inc text_line 		; increment text line
				lda text_line
				cmp #MAX_HEIGHT
				beq exit
				ldx #0
				jsr vram_set_address_text
				jmp skip_write
			skip_newline:
			cmp #CARRIAGE_RETURN
			beq skip_write
			cmp #ESCAPE_CHAR					; found '\' do this:
			bne skip_escape 					; didn't find '\' then skip
				iny 							; increase y offset
				lda (character_pointer),y 		; get next character
				dey 							; decrease y offset
				cmp #SLIDE_SEPERATOR 			; found 's' ?
				beq exit 						; exit this procedure
				cmp #TAB_CHAR 					; found 't' ?
				bne skip_escape 				; skip writing tab if there is none
					jsr write_tab
					increment_16i_pointer character_pointer
					jmp skip_write
			skip_escape:
				sta PPU_VRAM_IO 	; write it to the ppu io register
			skip_write:
			increment_16i_pointer character_pointer
			jmp text_loop 			; loop again
		exit:
			jsr display_slide_number0 ; display the slide idx
			rts 					; return from subroutine
	.endproc

	.proc display_next_slide_nt1
		ldy #0
		text_loop:
			lda (character_pointer_next),y 	; get current text byte (2 bytes address)
			beq exit 						; if it's 0, exit
			cmp #TAB
			bne skip_tab
				jsr write_tab
				jmp skip_write
			skip_tab:
			cmp #NEWLINE 			; check if it's a newline character
			bne skip_newline 		; if it isn't, branch
				inc text_line 		; increment text line
				lda text_line
				cmp #MAX_HEIGHT
				beq exit
				ldx #1
				jsr vram_set_address_text
				jmp skip_write
			skip_newline:
			cmp #CARRIAGE_RETURN
			beq skip_write
			cmp #ESCAPE_CHAR					; found '\' do this:
			bne skip_escape 					; didn't find '\' then skip
				iny 							; increase y offset
				lda (character_pointer_next),y 		; get next character
				dey 							; decrease y offset
				cmp #SLIDE_SEPERATOR 			; found 's' ?
				beq exit 						; exit this procedure
				cmp #TAB_CHAR 					; found 't' ?
				bne skip_escape 				; skip writing tab if there is none
					jsr write_tab
					increment_16i_pointer character_pointer_next
					jmp skip_write
			skip_escape:
				sta PPU_VRAM_IO 	; write it to the ppu io register
			skip_write:
			increment_16i_pointer character_pointer_next
			jmp text_loop 			; loop again
		exit:
			jsr display_slide_number1
			rts 					; return from subroutine
	.endproc

	.proc write_tab
		ldx #0				
		lda #SPACE 					; write a space
		@tab_writing_loop: 			; do enough spaces for the tab
			sta PPU_VRAM_IO
			inx 					; increment counter
			cpx #TAB_WIDTH 			; compare counter to tab width
			bne @tab_writing_loop 	; if we haven't done enough spaces, do it agains
		rts 
	.endproc

	.proc set_attributes
		save_registers
		ldy slide
		lda palettes, y
		sta current_palette
		vram_set_address (ATTRIBUTE_TABLE_0_ADDRESS)
		ora current_palette
		asl 
		asl 
		ora current_palette
		asl 
		asl 
		ora current_palette
		asl 
		asl 
		ora current_palette
		ldy #0
		@loop: 				; write all attributes to the vram
			sta PPU_VRAM_IO
			iny 
			cpy #$40
			bne @loop

		ldx #0
		jsr vram_set_address_text 	; set the vram address
		restore_regsiters
		rts 
	.endproc

	.proc set_attributes_next
		save_registers
		lda slide
		clc
		adc #1
		cmp number_of_slides
		bcc @no_wrap
			lda #0
		@no_wrap:
			tay
		lda palettes, y
		sta current_palette
		vram_set_address (ATTRIBUTE_TABLE_1_ADDRESS)
		ora current_palette
		asl 
		asl 
		ora current_palette
		asl 
		asl 
		ora current_palette
		asl 
		asl 
		ora current_palette
		ldy #0
		@loop: 				; write all attributes to the vram
			sta PPU_VRAM_IO
			iny 
			cpy #$40
			bne @loop

		ldx #1
		jsr vram_set_address_text 	; set the vram address
		restore_regsiters
		rts 
	.endproc

	.proc vram_set_address_text
		pha 
		txa 
		asl 
		asl 
		sta temp
		lda PPU_STATUS 		; load ppu status
		lda text_line 		; load the text line
		lsr 
		lsr 
		lsr 
		clc 
		adc #>NAME_TABLE_0_ADDRESS
		adc temp
		sta PPU_VRAM_ADDRESS		; write high byte
		lda text_line
		asl 				; multiply it with 32 (to get the y coord)
		asl 
		asl 
		asl 
		asl 
		clc 
		adc #PADDING_LEFT
		sta PPU_VRAM_ADDRESS		; write low byte
		pla 
		rts 
	.endproc

	.proc display_slide_number0 					; draws in bottom-right corner of the screen
		save_registers
		vram_set_address (SLIDE_INDEX_ADDR0) 	; set VRAM address to bottom-right

		lda slide 						; load current slide idx
		clc 
		adc #1 							; make it 1 based
		jsr print_two_digits 			; writes 2 chars (if necessary)

		lda #'/'
		sta PPU_VRAM_IO 				; write '/'

		lda number_of_slides
		jsr print_two_digits 			; writes 2 chars (if necessary)

		restore_regsiters
		rts 
	.endproc

	.proc display_slide_number1 					; draws in bottom-right corner of the screen
		save_registers
		vram_set_address (SLIDE_INDEX_ADDR1) 	; set VRAM address to bottom-right
		
		lda slide 						; load current slide idx
		clc 
		adc #2 							; add 1 to make it 1-based (first slide is 0) and add 1 more to show the slide number of the next slide
		jsr print_two_digits 			; writes 2 chars (if necessary)

		lda #'/'
		sta PPU_VRAM_IO 				; write '/'

		lda number_of_slides
		jsr print_two_digits 			; writes 2 chars (if necessary)

		restore_regsiters
		rts 
	.endproc

	.proc print_two_digits
		cmp #10
		bcc @one_digit 				; if A < 10 -> print single digit

		; ---- two-digit number ----
		ldy #0 						; tens = 0
		@tens_loop:
			cmp #10
			bcc @two_digits_ready
			sbc #10
			iny 					; tens++
			bne @tens_loop

		@two_digits_ready:
			sta temp_ones 			; store ones (0–9)
			tya 					; A = tens
			clc 
			adc #'0'
			sta PPU_VRAM_IO 		; print tens digit

			lda temp_ones 			; print ones digit
			clc 
			adc #'0'
			sta PPU_VRAM_IO
		rts 

		; ---- single-digit number ----
		@one_digit:
			clc 
			adc #'0'
			sta PPU_VRAM_IO
		rts 
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