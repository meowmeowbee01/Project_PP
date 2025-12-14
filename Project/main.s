.include "neslib.s"				; include neslib.s file
NEWLINE = $a					; symbol for new line in text
CARRIAGE_RETURN = $d			; symbol for carriage return in text
TAB = '	'						; symbol for tab in text
SPACE = ' '						; symbol for space in text

.segment "HEADER"
	INES_MAPPER = 0				; 0 = NROM
	INES_MIRROR = 1				; 0 = horizontal mirroring, 1 = vertical mirroring
	INES_SRAM   = 0				; 1 = battery backed SRAM at $6000-7FFF

	.byte "NES", $1a			; iNES header identifier
	.byte $02					; 2x 16KB PRG code
	.byte $01					; 1x  8KB CHR data
	.byte INES_MIRROR | (INES_SRAM << 1) | ((INES_MAPPER & $f) << $4)	; mirroring, sram usage and lower mapper bits
	.byte (INES_MAPPER & %11110000)										; upper mapper bits
	.byte 0, 0, 0, 0, 0, 0, 0, 0	; padding

.segment "VECTORS"
	.addr nmi		; when an NMI happens (once per frame if enabled), a jump to the label nmi will occur
	.addr reset		; when the processor first turns on or is reset, a jump to the label reset will occur
	.addr irq		; when an external interrupt is requested and IRQs are enabled, a jump to the irq label will occur

.segment "TILES"
	.incbin "PP.chr"	; includes bin file of letters and symbols drawing

.segment "ZEROPAGE"
	text_line: .res 1				; current drawn roow
	text_column: .res 1				; current drawn column
	slide: .res 1					; current slide inxed
	remaining_input_cooldown: .res 1; Timer to prevent double click
	current_palette: .res 1			; current color pallete
	character_pointer: .res 2 		; points to start of slide
	temp_pointer: .res 2 			; points to start of next slide
	number_of_slides: .res 1		; total number of slides
	scroll_x: .res 1				; scroll offset
	current_nametable: .res 1		; active nametable
	temp: .res 1					; general use

.segment "OAM"
	oam: .res $100					; reserve 256 bytes OAM

.segment "BSS"
	palette: .res $20				; reserve 32 bytes for palette

.segment "CODE" 	; main code segment for the program
	.include "settings.s"	; include settings.s file
	.include "audio.s"		; inculde audio.s file
	SLIDE_INDEX_ADDR0 = NAME_TABLE_0_ADDRESS + (INDEX_Y_POS * $20) + INDEX_X_POS	; adress in nametable 0 where slide index text will draw
	SLIDE_INDEX_ADDR1 = NAME_TABLE_1_ADDRESS + (INDEX_Y_POS * $20) + INDEX_X_POS	; adress in nametable 1 where slide index text will draw
	MAX_WIDTH = $20 - PADDING_RIGHT		; maximum width text+symbols one row that fit
	MAX_HEIGHT = $1e - PADDING_BOTTOM	; max rows that fit

	text:
		.incbin "content.txt"	; include binary file containing text
		.byte 0					; add null at the end to know end of slide

	.proc irq
		rti 		; do nothing if an IRQ happens
	.endproc

	.proc reset			; reset on reset button/powered on powerpoint
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
			bit PPU_STATUS	; ppu statues into flags
			bpl @vblankwait1 ; loop untill vblank flag set

		lda #0				; value we write in each register -> A
		ldx #0				; loop counter -> X
		@clear_memory:		; 8 blocks of memory X 256 = 2K cleared
			sta 0, x		; store whatever a has in given address with offset in X
			sta $0100, x	; ^^
			sta $0300, x	; ^^
			sta $0400, x	; ^^
			sta $0500, x	; ^^
			sta $0600, x	; ^^
			sta $0700, x	; ^^
			lda #$ff		; ^^
			sta $0200, x	; ^^
			lda #0			; ^^
			inx 			; next byte
			bne @clear_memory 	; loop will stop when X goes back to 0

		jsr clear_sprites 		; clear oam (sprites)

		@vblankwait2:	; second wait for vblank, PPU is ready after this
			bit PPU_STATUS		; ppu statues into flags
			bpl @vblankwait2	; loop untill vblank flag set

		lda #%10001000
  		sta PPU_CONTROL ; enable nmi

		ldx #0 			; initialize palette table
		@paletteloop:	; loop to put palette in ram
			lda default_palette, x	; load x byte of palette in a
			sta palette, x			; store palette into ram
			inx 					; next byte
			cpx #$20				; check if 32 byte reached
			bcc @paletteloop		; if not, loop

		jsr ppu_off 			; turn rendering off
		clear_nametable(NAME_TABLE_0_ADDRESS)	; clear background nametable 0
		clear_nametable(NAME_TABLE_1_ADDRESS)	; clear background nametable 1

		jsr setup_first_slide			; initial slide state
		jsr set_number_of_slides		; calculates and stores total of slides
		jsr display_current_slide		; draw current slide

		jsr ppu_update					; pu update after off

		jsr audio_init						; <--- THIS IS UPPOSED TO BE THE ONLY PLACE WHERE audio_init is called

		jmp mainloop					; start the main loop
	.endproc

	.proc nmi
		save_registers	; save registers
		lda #0			; a = 0
		cmp remaining_input_cooldown		; check remaining input cooldown if 0
		beq skip_decrement					; if 0 skip decrement cooldown
			dec remaining_input_cooldown	; decrement cooldown
		skip_decrement:						

		; transfer current palette to PPU
		vram_set_address $3f00				; vram to palette adresse
		ldx #0 ; transfer the 32 bytes to VRAM
		@loop:					
			lda palette, x		; load a palette byte
			sta PPU_VRAM_IO		; store into ppu
			inx 				; increment for next
			cpx #$20			; check if 32 
			bcc @loop			; if not 32 loop

		; write current scroll and control settings
		lda scroll_x			; load x scroll a
		sta PPU_SCROLL			; write x scroll into ppu
		lda #0					; load y scroll a
		sta PPU_SCROLL			; write y scroll into ppu
		lda ppu_ctl0
		sta PPU_CONTROL
		lda ppu_ctl1
		sta PPU_MASK			

		jsr audio_update				; <---- PRETTY SELF EXPLANATORY

		; flag PPU update complete
		ldx #0			; x=0
		stx nmi_ready	; nmi done

		restore_regsiters	; restore rregisters
		rti					; return from interrupt
	.endproc

	.proc mainloop
		lda remaining_input_cooldown 	; keep looping till remaining input cooldown is 0
		bne mainloop					; if cooldown not 0  loop
		jsr gamepad_poll 				; keep looping till there is an input
		lda gamepad						; load input state
		and #PAD_A|PAD_RIGHT			; check next slide input pushed
		bne next_slide					; if yes go next slide
		lda gamepad						; load input state
		and #PAD_B|PAD_LEFT				; check prev slide input pushed
		bne prev_slide					; if yes go to next slide
		lda JOYPAD2						; load input 2nd control (gun)
		and #GUN_TRIGGER				; check if gun trigger
		bne next_slide					; if yes go next slide
		jmp mainloop					; nothing happend so loop back to mainloop
		next_slide:					; next slide procedures
			jsr audio_play_next 					; <---- PRETTY SELF EXPLANATORY
			lda #INPUT_COOLDOWN 					; set remaining input cooldown
			sta remaining_input_cooldown			; store cooldown into input cooldown
			jsr ppu_off								; turn of ppu for safety
			clear_nametable(NAME_TABLE_1_ADDRESS)	; clear nametable 1
			set_nametable_1							; select nametable 1
			jsr go_to_next_slide					; update slide index
			jsr display_current_slide				; display new slide in nametable 
			lda #SCROLL_SPEED						; scrollspeed to a
			beq skip_scroll_forward 		; skip scroll when speed is 0
				jsr scroll_next				; do scrolling
			skip_scroll_forward:			; skip scrolling 
			jsr ppu_off						; ppu off for safety
			clear_nametable(NAME_TABLE_0_ADDRESS)	; clear nametable 0
			set_nametable_0							; set nametable 0
			jsr display_current_slide				; draw current slide (nametable 0)
			lda #0									; a =0 
			sta scroll_x							; scroll set to 0 so positioned right
			jsr ppu_update							; ppu update after off for a bit
			jmp mainloop							; back to mainloop
		prev_slide:						; prev slide procedure
			jsr audio_play_prev				; <---- PRETTY SELF EXPLANATORY
			lda #INPUT_COOLDOWN 			; set remaining input cooldown
			sta remaining_input_cooldown	; store cooldown into input cooldown
			jsr ppu_off						; turn of ppu for safety
			clear_nametable(NAME_TABLE_0_ADDRESS)	; clear nametable 0
			clear_nametable(NAME_TABLE_1_ADDRESS)	; clear nametable 1
			set_nametable_1							; set nametable 1
			jsr display_current_slide				; draw crrent to nametable 1
			set_nametable_0				; leave this here (it needs to be 0 for the go to previous slide subroutine)
			jsr go_to_previous_slide				; update slide index
			jsr display_current_slide				; draw prev slide into nametable 0
			lda #$ff ; screen width
			sta scroll_x	; scroll to nametable 1
			jsr scroll_next ; do scroll 
			jsr ppu_update	; delayed ppu update
			jmp mainloop	; back to main loop
	.endproc

	.proc set_number_of_slides
		ldx #1	; slide counter
		loop:
			increment_16i_pointer character_pointer	; go next char with pointer
			ldy #0	; y = 0
			lda (character_pointer), y 	; y is 0 so just the character the pointer points to
			beq exit 					; if it's 0, we're past the last slide
			cmp #ESCAPE_CHAR			; check if escape char
			bne loop					; if not loop back
				ldy #1					; y = 1
				lda (character_pointer), y 	; check the next character
				cmp #ESCAPE_CHAR		; check if escape char
				bne skip_escape_escape	; if not double escape see skip escape escape
					increment_16i_pointer character_pointer 	; double escape, so skip 2nd escpae
					jmp loop									; back to loop
				skip_escape_escape:	
				cmp #SLIDE_SEPERATOR	; next slide afte escape?
				bne loop				; if no loop
				ldy #2					; y = 2
				lda (character_pointer), y 	; check the character after slide seperator
				beq exit 					; if it's 0, there's a trailing slide terminator
				inx 					; next slide detected so inc slide counter
				jmp loop				; back to loop
		exit:
			assign_16i character_pointer, text	; set current slide pointer to the first slide
			stx number_of_slides 				; store number of slides x
			rts 								; return to subroutine
	.endproc

	.proc setup_first_slide
		lda #0		; a=0 
		sta slide	; current slide 0
		sta current_nametable	; set nametable 0
		assign_16i character_pointer, text ; point to start slide
		assign_16i temp_pointer, text	; temp pointer to start slide
		set_padding						; apply padding
		jsr set_attributes				; initialize attribute table
		rts 							; return ti subroutine
	.endproc

	.proc scroll_next
		lda scroll_x	; load current scroll a
		beq forward		; if scroll 0 go forward tag
		back_loop:	; scrolling backwards
			sta scroll_x	; update scroll 
			tay 			; save scroll to y
			jsr ppu_update	; wait nmi
			lda remaining_input_cooldown	; load input cooldown
			bne skip_input_backwards		; if cooldown not 0 skip input
				jsr gamepad_poll			; detect input state
				lda gamepad					; load input state a
				and #PAD_A|PAD_RIGHT|PAD_B|PAD_LEFT	; check button pressed for skip
				bne skipped					; if presed, skip
				lda JOYPAD2					; load a input state joypad2
				and #GUN_TRIGGER			; check trigger pressed
				bne skipped					; if pressed skip
			skip_input_backwards:	; continue scroll, nothing pressed
			tya 	; scroll value back to a from y
			clc 	; clear carry
			cmp #SCROLL_SPEED 		; end transition when left side reached
			bcc done	; if less then scroll speed, end transition
			sec 		; set carry
			sbc #SCROLL_SPEED	; move scroll position left with scroll speed
			jmp back_loop		; loop scrolling
		forward:	; scrolling forward
		lda #0			; start scroll 0
		forward_loop:	; scroll loop
			sta scroll_x	; scroll x update current scroll in a
			tay 			; save current scroll y
			jsr ppu_update 	; wait nmi
			lda remaining_input_cooldown	; load input cooldown
			bne skip_input_forward			; if cooldown not 0 skip input
				jsr gamepad_poll			; detect input state
				lda gamepad					; load input state a
				and #PAD_A|PAD_RIGHT|PAD_B|PAD_LEFT ; check button pressed for skip
				bne skipped					; if presed, skip
				lda JOYPAD2					; load a input state joypad2
				and #GUN_TRIGGER			; check trigger pressed
				bne skipped					; if pressed skip
			skip_input_forward:	; continue scroll, nothing pressed
			tya 				; restore scroll to a from y
			clc 				; clear carry
			adc #SCROLL_SPEED	; add scroll speed a to scroll
			bcs done			; if carry set scroll doen (set cause more than screen width)
			jmp forward_loop	; continue loop
		skipped:
			lda #INPUT_COOLDOWN	; reset cooldown
			sta remaining_input_cooldown	; reset cooldown
		done:
			lda #0	; a 0 fir scroll pos
			sta scroll_x	; reset scroll
			rts 			; return subroutine
	.endproc

	.proc go_to_next_slide
		set_padding	; set padding
		ldx #0
		ldy #0
		jmp skip_increment 				; character_pointer points at the end of previous slide so don't increment the first time
		find_next_slide: 	 			; proceed if they are equal
			increment_16i_pointer character_pointer	; go next char
			skip_increment:
			lda (character_pointer), y 	; y is 0 so just the character the pointer points to
			beq reset_slides 			; if it's 0, go back to first slide since there's a 0 after the content
			cmp #ESCAPE_CHAR			; char is escape char?
			bne find_next_slide			; if no esc char continue next char
				ldy #1					; increment to next char
				lda (character_pointer), y 		; check the next character
				ldy #0					; go back
				cmp #ESCAPE_CHAR		; check double escpae
				bne skip_escape_escape	; if no double escape next check
					increment_16i_pointer character_pointer	; increase char to skip second escape char
					jmp find_next_slide	; loop back
				skip_escape_escape:
				cmp #SLIDE_SEPERATOR	; is slide seperator?
				bne find_next_slide		; if no slide sep loop again
		
		add16i character_pointer,2 				; skip over \s
		lda (character_pointer), y				; load char after s
		cmp #CARRIAGE_RETURN					; is char CR
		bne skip_CR_skip						; if not CR skip
			increment_16i_pointer character_pointer ; skip over CR
		skip_CR_skip:
		increment_16i_pointer character_pointer 	; skip over newline
		inc slide		; inc slide index
		jmp attributes	; update attributes

		reset_slides:
			assign_16i character_pointer, text	; set current slide pointer to the first slide
			lda #0		
			sta slide	; reset slide index first slide
		
		attributes:
			jsr set_attributes	; set attribute current slide

		exit:
			rts 	; return to subroutine
	.endproc

	.proc go_to_previous_slide
		lda slide						; load current slide
		cmp #0							; if this is the first slide, loop all the way to the end
		bne not_first_slide				; skip if slide index != 0
			ldy #1							; y will serve as slide index
			slide_loop1:					; loop to reach last slide:
				save_registers				; save registers for later
				jsr go_to_next_slide		; advance next slide
				restore_regsiters			; load registers
				iny 						; since we are on the next slide, inc y
				cpy number_of_slides		; compare to total amount of slides
				bne slide_loop1				; not end? go back
				jmp exit					; is end -> exit
		not_first_slide:
		save_registers			; save registers for later
		jsr setup_first_slide	
		restore_regsiters		; load registers
		sec 		; set carry for sub
		sbc #1		; a -1 for prev slide
		slide_loop2:	; loop to prev slide
			cmp #0		
			beq exit	; if slide 0 exit
			pha 		; save a
			jsr go_to_next_slide	;go next slide
			pla 		; load a
			sec 		; set carry for sub
			sbc #1		; a -1 for prev slide
			jmp slide_loop2	; loop
		exit:
			rts ; return subroutine
	.endproc

	.proc display_current_slide
		set_padding	; set padding
		jsr set_attributes	; apply attributes
		assign16i_pointer temp_pointer, character_pointer	; copy char point to temp point
		ldy #0	; y = 0 for char pointing
		text_loop:
			lda (temp_pointer),y 	; get current text byte (2 bytes address)
			bne skip_exit 				; if it's 0, exit
				jmp exit				; exit if not 0
			skip_exit:
			cmp #TAB		; is tab char?
			bne skip_tab	; if not skip
				jsr write_tab	; do tab writing subroutine
				jmp skip_write	; skip write to loop
			skip_tab:
			cmp #NEWLINE 			; check if it's a newline character
			bne skip_newline 		; if it isn't, branch
				inc text_line 		; increment text line
				lda text_line		; load text line
				cmp #MAX_HEIGHT		; see height max reached
				beq exit			; if max exit
				set_padding_left	; reset to left padding
				jsr vram_set_address_text	; update vram adress
				jmp skip_write				; done newline, skip write to loop
			skip_newline:
			cmp #CARRIAGE_RETURN	; check if CR
			beq skip_write			; skip write CR
			cmp #ESCAPE_CHAR					; found '\' do this:
			bne skip_escape 					; didn't find '\' then skip
				sta temp						; save \ temp
				iny 							; increase y offset
				lda (temp_pointer),y 			; get next character
				dey 							; decrease y offset
				cmp #SLIDE_SEPERATOR 			; found 's' ?
				beq exit 						; exit this procedure
				cmp #TAB_CHAR 					; found 't' ?
				bne skip_tab_escape 			; skip writing tab if there is none
					jsr write_tab				; write tabs in subroutine
					increment_16i_pointer temp_pointer	;next char
					jmp skip_write				; skip writing and loop to next
				skip_tab_escape:				
				cmp #ESCAPE_CHAR				; check escape char
				bne skip_escape_escape			; if not skip this
					increment_16i_pointer temp_pointer	;go next char
				skip_escape_escape:
				lda temp						; load \ back to a
			skip_escape:
				sta PPU_VRAM_IO 	; write the character to the ppu io register
				inc text_column		; increment one columnt
				lda text_column		; load next column
				clc 				; clear carry
				cmp #MAX_WIDTH		; check max width reached
				bcc skip_write		; if not skip this
					inc text_line 		; increment text line
					lda text_line		; load updated line
					cmp #MAX_HEIGHT		; check max height reached
					bcs exit			; if reached, screen full so skip draw
					set_padding_left	; reset padding to left again
					jsr vram_set_address_text	; update vram adress 
			skip_write:
			increment_16i_pointer temp_pointer	;next char
			jmp text_loop 				; loop again
		exit:
			jsr display_slide_number 	; display the slide idx
			rts 						; return from subroutine
	.endproc

	.proc write_tab
		ldx #0						; 0 to x for tab counter
		lda #SPACE 					; write a space
		@tab_writing_loop: 			; do enough spaces for the tab
			sta PPU_VRAM_IO			; write space to nametable
			inc text_column			; inc column
			inx 					; increment counter
			cpx #TAB_WIDTH 			; compare counter to tab width
			bne @tab_writing_loop 	; if we haven't done enough spaces, do it agains
		rts 						; return from subroutine
	.endproc

	.proc set_attributes
		save_registers					; save registers for later
		lda current_nametable			; x = 0 for current slide, x = 1 for next slide
		asl 							; shift left twice for attribute table selection
		asl 							; ^^
		adc #>ATTRIBUTE_TABLE_0_ADDRESS	; add high byte 
		sta PPU_VRAM_ADDRESS			; write high byte to ppu vram adress
		lda #$c0 						; low byte load
		sta PPU_VRAM_ADDRESS			; write low byte to ppu vram adress

		ldy slide				; y = current slide
		lda palettes, y			; load palettes this slide
		sta current_palette		; store current palette
		ora current_palette		; set the byte to 000000X where x is the current palette
		asl 					; shift it left twice so it becomes 0000X00
		asl 					; ^^
		ora current_palette		; or it with the current palette again so it becomes 0000XX
		asl 					; shift it left twice once again for 00XX00
		asl 					; ^^
		ora current_palette		; once again or it with the palette so it now is 00XXX
		asl 					; shift it for a last time so it now becomes XXX00
		asl 					; ^^
		ora current_palette		; and ora it a final time so the byte now is XXXX where each X represent the current palette using 2 bits
		ldy #0
		@loop: 				; write all attributes to the vram
			sta PPU_VRAM_IO	; write attibutes vram
			iny 			; increment y for next
			cpy #$40		; check if 64 bytes reached 
			bne @loop		; loop if not

		jsr vram_set_address_text 	; set the vram address
		restore_regsiters			; restore register
		rts 						; return to subroutine
	.endproc

	.proc vram_set_address_text
		pha 	; save a
		lda current_nametable			; x = 0 for current slide, x = 1 for next slide
		asl 	; shift left twice
		asl 	; ^^
		sta temp	; store nametable offset temp
		lda PPU_STATUS 		; load ppu status
		lda text_line 		; load the text line
		lsr 	; shift right thrice
		lsr 	; ^^
		lsr 	; ^^
		clc 	; clear carry for addition
		adc #>NAME_TABLE_0_ADDRESS	; add high byte nametable 0
		adc temp					; add nametable  offset
		sta PPU_VRAM_ADDRESS		; write high byte
		lda text_line		; load reload text line
		asl 				; multiply it with 32 (to get the y coord)
		asl 				; ^^
		asl  				; ^^
		asl  				; ^^
		asl  				; ^^
		clc 				; clear carry for addition
		adc text_column		; add column 
		sta PPU_VRAM_ADDRESS		; write low byte
		pla 	; restore a
		rts 	; return to subroutine
	.endproc

	.proc display_slide_number 					; draws in bottom-right corner of the screen
		save_registers					; save registers
		lda current_nametable					; load the current name_table
		bne name_table_1						; if it is not 0, go to the section for nametable 1
			vram_set_address (SLIDE_INDEX_ADDR0) 	; set VRAM address to bottom-right of nametable 0
			jmp index_set						; and go to the section where the index is set
		name_table_1:							; if it is 1
			vram_set_address (SLIDE_INDEX_ADDR1) ; set the vram address to the bottom right of nametable 1
		index_set:
		lda slide 						; load current slide idx
		clc 							; clear carry for addition
		adc #1 							; make it 1 based
		jsr print_two_digits 			; writes 2 chars (if necessary)

		lda #INDEX_SEPERATOR			; load index sep to a
		sta PPU_VRAM_IO 				; write an index seperator

		lda number_of_slides			; load numbers of slide a
		jsr print_two_digits 			; writes 2 chars (if necessary)

		restore_regsiters				; restore registers
		rts 							; return to subroutine
	.endproc

	.proc print_two_digits
		cmp #10						; check if total slides 2 digits
		bcc @one_digit 				; if A < 10 -> print single digit

		; ---- two-digit number ----
		ldy #0 						; tens = 0
		@tens_loop:
			cmp #10					; is a less 10
			bcc @two_digits_ready	; if less, tens calc done
			sbc #10					; subtract 10
			iny 					; tens++
			bne @tens_loop			; repeat till value <10

		@two_digits_ready:
			sta temp 			; store ones (0–9)
			tya 					; A = tens
			clc 					; clear carry for add
			adc #'0'				; tens digit to char
			sta PPU_VRAM_IO 		; print tens digit

			lda temp 			; print ones digit
			clc 				; clear carry for addition
			adc #'0'			; convert ones digit  to char
			sta PPU_VRAM_IO		; write digit
		rts 					; return to subroutine

		; ---- single-digit number ----
		@one_digit:
			clc 		; clear carry for addition
			adc #'0'	; connvert digit to char
			sta PPU_VRAM_IO	; draw ppu
		rts 			; return from subroutine
	.endproc

.segment "RODATA"
	default_palette: 	; background palette
		.byte $0f, $15, $16, $26 ; red
		.byte $0f, $1a, $2a, $29 ; green
		.byte $0f, $11, $21, $2c ; blue
		.byte $0f, $30, $10, $00 ; gray
						; sprite palette (unused)
		.byte $0f, $28, $21, $11	; unused
		.byte $0f, $26, $28, $17	; unused
		.byte $0f, $1b, $2b, $3b	; unused
		.byte $0f, $12, $22, $32	; unused