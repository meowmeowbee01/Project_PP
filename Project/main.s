.segment "HEADER"
	NES_MAPPER = 0
	NES_MIRROR = 0
	NES_SRAM = 0
	.byte "NES", $1a 	; identification
	.byte 2 			; 2x 16KB PRG code
	.byte 1 			; 1x  8KB CHR data
	.byte NES_MIRROR | (NES_SRAM << 1) | ((NES_MAPPER & $f) << 4) ; mirror mode and sram and mapper
	.byte 0             ; mapper
	.byte 0, 0, 0, 0, 0, 0, 0, 0 	; misc things (will later add)

;*****************************************************************
; Import both the background and sprite character sets
;*****************************************************************
.segment "TILES"
	.incbin "PP.chr"

.segment "VECTORS"
	.word nmi 	; When an NMI happens (once per frame if enabled) the label nmi
	.word reset ; When the processor first turns on or is reset, it will jump to the label reset
	.word irq 	; External interrupt IRQ (unused)

.segment "ZEROPAGE"
	paddr: .res 2     ; pointer to 16 bit address
	time: .res 2    
	lasttime: .res 1 
	SEED0: .res 2
	SEED2: .res 2 
	level: .res 1
	animate: .res 1
	enemydata: .res 20
	enemycooldown: .res 1
	temp: .res 10
	score: .res 3
	update: .res 1 
	highscore: .res 3
	lives: .res 1
	player_dead: .res 1

	;update flags:
	;bit 0:   is set if the score is updated (so we dont do calculations if we dont need it)
	;bit 1:   is set if the high score has been updated (same reason)
	;bit 2:   is set if we need to display the player's lives
	;bit 3:   is set if the game over message needs to be displayed
	;bit 4:   not used yet
	;bit 5:   not used yet 
	;bit 6:   not used yet
	;bit 7:   not used yet  

.segment "OAM"
	oam: .res 256

.include "neslib.s"

;*****************************************************************
; Remainder of normal RAM area
;*****************************************************************
.segment "BSS"
	palette: .res 32 

.segment "STARTUP"

.segment "CHARS"

.segment "CODE" ; Main code segment for the program

gameovertext:
.byte " G A M E O V E R",0

irq: ;currently nothing yet for the irq
	rti 

.proc reset
	sei 
	cld 
	lda #0
	sta PPU_CONTROL 	; disable rendering
	sta PPU_MASK 
	sta APU_DM_CONTROL
	lda #$40
	sta JOYPAD2 		; disable apu frame irq

	ldx #$ff ; init the stack
	txs 

	bit PPU_STATUS
	: ; wait for vblank
		bit PPU_STATUS
		bpl :-

	lda #0
	ldx #0
	clear_ram:
		sta $0100,x
		sta $0200,x
		sta $0300,x
		sta $0400,x
		sta $0500,x
		sta $0600,x
		sta $0700,x
		inx 
		bne clear_ram

		lda #$ff
		ldx #0
	clear_oam:
		sta oam, x 
		inx 
		inx 
		inx 
		inx 
		bne clear_oam

		bit PPU_STATUS
	: ; wait for vblank
		bit PPU_STATUS
		bpl :-

	

	lda #%10001000
	sta PPU_CONTROL ; enable nmi

	jmp main
.endproc

.proc nmi
	; save registers
	pha 
	txa 
	pha 
	tya 
	pha 

	; increment our time tick counter
	inc time
	bne :+
		inc time + 1
	:

	bit PPU_STATUS

	; transfer current palette to PPU
	vram_set_address $3f00
	ldx #0 ; transfer the 32 bytes to VRAM
		@loop:
			lda palette, x
			sta PPU_VRAM_IO
			inx 
			cpx #$20
			bcc @loop
		
	lda #%00000001 			; has the score updated?
	bit update
	beq @skipscore
		jsr display_score 	; display score
		lda #%11111110 		; reset score update flag
		and update
		sta update
	@skipscore:

	lda #%00000010 				; has the high score updated?
	bit update
	beq @skiphighscore
		jsr display_highscore 	; display high score
		lda #%11111101 			; reset high score update flag
		and update
		sta update
	@skiphighscore:

	lda #%00001000 ; does the game over message need to be displayed?
	bit update
	beq @skipgameover
		vram_set_address (NAME_TABLE_0_ADDRESS + 14 * 32 + 7)
		assign_16i text_address, gameovertext 
		jsr write_text
		lda #%11110111 ; reset game over message update flag
		and update
		sta update
	@skipgameover:

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

	; restore registers and return
	pla 
	tay 
	pla 
	tax 
	pla 
	rti 
.endproc

.proc main
 	; main application - rendering is currently off1

 	; initialize palette table
 	ldx #0
	@paletteloop:
		lda default_palette, x
		sta palette, x
		inx
		cpx #$20
		bcc @paletteloop

	resetgame:
		jsr clear_sprites

		; draw the title screen
		jsr display_title_screen

		; set our game settings
		lda #VBLANK_NMI|BG_0000|OBJ_1000
		sta ppu_ctl0
		lda #BG_ON|OBJ_ON
		sta ppu_ctl1

		jsr ppu_update

	; wait for a gamepad button to be pressed
	titleloop:
		jsr gamepad_poll
		lda gamepad
		and #PAD_A|PAD_B|PAD_START|PAD_SELECT
		beq titleloop

	; set our random seed based on the time counter since the splash screen was displayed
	lda time
	sta SEED0
	lda time+1
	sta SEED0+1
	jsr randomize
	sbc time+1
	sta SEED2   
	jsr randomize
	sbc time
	sta SEED2+1

	mainloop:
		jmp mainloop 			; redo of healer is a great anime, watch episode 1 (at least 10mins). You'll enjoy it
.endproc

.proc display_title_screen
	jsr ppu_off 		; turn rendering off
	jsr clear_nametable ; clear nametable

	vram_set_address (NAME_TABLE_0_ADDRESS + 4 * 32 + 6) 	; set the vram address (and place the text on the fifth line at x location 6)
	assign_16i text_address, hello_text 					; put the text in the address
	jsr write_text

	vram_set_address (NAME_TABLE_0_ADDRESS + 20 * 32 + 6)	; set next vram address (and place the text on the 21st line at x location 6)
	assign_16i text_address, press_play_text 				; put the second text in the address
	jsr write_text

	vram_set_address (ATTRIBUTE_TABLE_0_ADDRESS + 8) 		; sets the title text to use the second palette
	assign_16i paddr, title_attributes

	ldy #0
	@loop: 				; write all attributes to the vram
		lda (paddr),y
		sta PPU_VRAM_IO
		iny 
		cpy #8
		bne @loop

	jsr ppu_update  ; update the ppu
	rts 
.endproc

.proc randomize 	; easier rand function
	lda SEED0 		; load seed 0
	lsr 			; logical shift right
	rol SEED0 + 1 	; rotate left the low byte
	bcc @noeor 		; really some random shit at this point
		eor #$B4 	; yes xor it with the most random number
	@noeor: 		; i dont even know at this point
	sta SEED0 		; store the new a in the seed
	eor SEED0 + 1   ; another xor for more randomness
	rts 
.endproc

.proc rand 			; better rand function
	jsr rand64k 	; basically do a shit ton of shifts and xor....
	jsr rand32k
	lda SEED0 + 1
	eor SEED2 + 1
	tay 
	lda SEED0
	eor SEED2
	rts 
.endproc

.proc rand64k
	lda SEED0 + 1
	asl 
	asl 
	eor SEED0 + 1
	asl 
	eor SEED0 + 1
	asl 
	asl 
	eor SEED0 + 1
	asl 
	rol SEED0
	rol SEED0 + 1
	rts 
.endproc

.proc rand32k
	lda SEED2 + 1
	asl 
	eor SEED2 + 1
	asl 
	asl 
	ror SEED2
	rol SEED2 + 1
	rts 
.endproc

.proc add_score 
	clc ;each byte is used  to represent 2 numbers of the score so if the score is 543299 then the first byte stores 99, the second one 32 and the last one 54
	adc score ;adds the value in a to the current score
	sta score 
	cmp #99     ;compare to 99
	bcc @skip   ;if it's smaller or equal to 99 skip the rest

	sec         ;i swear, this carry flag is driving me insane
	sbc #100  ;subtract 100 from this score
	sta score   ;store the new score

	inc score+1 ;increment the next score
	lda score+1 ;get the new current score
	cmp #99     ;once again compare to 99
	bcc @skip   ;if it's less or equal, skip the rest

	sec         ;-_-
	sbc #100  ;remove 100 from the current a value
	sta score+1 ;update that part

	inc score+2 ;increment last part of the score
	lda score+2 ;get the numbers on position of x: xx0000 (so the 10k's, and 100k's)
	cmp #99     ;compare to 99
	bcc @skip   ;if its less or equal to 99, skip the rest

	sec         ;https://youtu.be/dQw4w9WgXcQ?si=FEQCmkhkzpgXjq91 for explanation
	sbc #100  ;remove 100
	sta score+2 ;store it again (we do nothing else since we have no extra bytes to store the number)

	@skip:
	lda #%000000001
	ora update
	sta update ;set the updatescore flag to 1
	rts
.endproc

.proc subtract_score ;if you dont understand this part, you're stupid and you k.. go to the add part to try and understand it
	sta temp ;save point penalty

	sec       ;d,qjhdkjzlfnzzl
	lda score ;get current score
	sbc temp  ;apply the point penalty
	sta score ;store new value
	bcs @skip ;jump if the number is positive

	clc       ;LKQJHDZZZZZZZjkDQHLZHDJKQLHDq
	adc #100  ;add 100 to the score
	sta score   ;store new score

	dec score+1 ;decrement the second score byte
	bcs @skip   ;if that's positive, skip the rest

	clc         ; i will be lowtiergod
	lda score+1 ;get current second byte of score
	adc #100  ;add 100 the value so it makes sense
	sta score+1 ;store new second byte of score

	dec score+2 ;decrement the last byte
	bcs @skip   ;if its positive skip

	lda #0      ;reset score entirely
	sta score+2
	sta score+1
	sta score

	@skip:
	lda #%00000001  
	ora update
	sta update    ;set update score flag
	rts
.endproc

.proc display_score
	vram_set_address (NAME_TABLE_0_ADDRESS + 27 * 32 + 6) ;the location of the score
	lda score+2         ;get the 2 decimal numbers from our score (xa0000)
	jsr dec99_to_bytes
	stx temp            ;store the numbers temporarily
	sta temp+1

	lda score+1         ;get middle 2 decimal numbers from our score (00xa00)
	jsr dec99_to_bytes  ;get the 2 seperate number
	stx temp+2          ;store the extracted values
	sta temp+3

	lda score           ;get the lower 2 decimal numbers (0000xa)
	jsr dec99_to_bytes  ;get the 2 seperate numbers
	stx temp+4          ;store the extracted values
	sta temp+5

	ldx #0
	@loop:        ;loop over all the numbers
		lda temp,x  ;get the current number
		clc         ;I hope jesus finds their way to me
		adc #48     ;add 48 since 48 is the starting pos of our tile characters
		sta PPU_VRAM_IO   ;write it to ppu register
		inx         ;increment x
		cpx #6      ;check if we have looped 6 times
		bne @loop

	lda #48         ;write a trailing 0 for fun
	sta PPU_VRAM_IO 
	vram_clear_address  ;clear address
	rts
.endproc

.proc display_highscore
	vram_set_address (NAME_TABLE_0_ADDRESS + 1 * 32 + 13)

	lda highscore+2 ; transform each decimal digit of the high score
	jsr dec99_to_bytes
	stx temp
	sta temp+1

	lda highscore+1
	jsr dec99_to_bytes
	stx temp+2
	sta temp+3

	lda highscore
	jsr dec99_to_bytes
	stx temp+4
	sta temp+5

	ldx #0 ; write the six characters to the screen
	@loop:
	lda temp,x
	clc
	adc #48
	sta PPU_VRAM_IO
	inx
	cpx #6
	bne @loop
	lda #48 ; write trailing zero
	sta PPU_VRAM_IO

	vram_clear_address
	rts
.endproc

title_text:
	.byte "M E G A B L A S T",0

hello_text:
	.byte "Hello World",0

press_play_text:
	.byte "PRESS FIRE TO BEGIN",0

title_attributes:
	.byte %00000101,%00000101,%00000101,%00000101
	.byte %00000101,%00000101,%00000101,%00000101

.segment "RODATA"
	default_palette:
	;background palette
		.byte $0F,$15,$26,$37
		.byte $0F,$19,$29,$39
		.byte $0F,$11,$21,$31
		.byte $0F,0,$10,$30
		;sprite palette
		.byte $0F,$28,$21,$11
		.byte $0F,$26,$28,$17
		.byte $0F,$1B,$2B,$3B
		.byte $0F,$12,$22,$32 
 
	game_screen_scoreline:
		.byte "SCORE 0000000"
