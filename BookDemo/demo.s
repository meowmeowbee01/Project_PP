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
	.incbin "megablast.chr"

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
	; transfer sprite OAM data using DMA
	lda #>oam
	sta SPRITE_DMA

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

	lda #%00000100 ; display the players lives
	bit update
	beq @skiplives
		jsr display_lives
		lda #%11111011
		and update
		sta update
	@skiplives:

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
 	; main application - rendering is currently off
	lda #1 ; set initial high score to 1000
	sta highscore + 1

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

	; set up ready for a new game
	lda #1
	sta level
	jsr setup_level

	lda #0 			; reset the player's score
	sta score
	sta score + 1
	sta score + 2
	lda #%00000001 	; set flag so the current score will be displayed
	ora update
	sta update

	lda #5 		; set the players starting lives
	sta lives
	lda #0 		; reset our player_dead flag
	sta player_dead 

	jsr display_game_screen

	jsr display_player

	jsr ppu_update

	mainloop:
		lda time
		cmp lasttime 		; ensure the time has actually changed
		beq mainloop
		sta lasttime 		; time has changed update the lasttime value

		lda lives 			; get the lives
		bne @notgameover 	; if it's not 0 jump to next section
		lda player_dead 	; load player dead status
		cmp #1 				; see if the flag is set
		beq @notgameover 	; if it isn't

		cmp #$df 			; compare to the last 4 bits
		beq resetgame 		; if all those bits are set, reset the game 

		cmp #%00010100 			; if bit 5 and 3 are set
		bne @notgameoversetup 	; dont show game over screen
			lda #%00001000 		; set the game over flag
			ora update
			sta update
		@notgameoversetup:
		inc player_dead 		; start the setup of the game over screen
		jmp mainloop 			; so it can show it next loop (also instantly jump back to the loop)

		@notgameover:
			jsr player_actions 		; do the player actions
			jsr move_player_bullet 	; move bullet
			jsr spawn_enemies 		; spawn enemies
			jsr move_enemies 		; move them
			jmp mainloop 			; redo of healer is a great anime, watch episode 1 (at least 10mins). You'll enjoy it
.endproc

.proc display_title_screen
	jsr ppu_off 		; turn rendering off
	jsr clear_nametable ; clear nametable

	vram_set_address (NAME_TABLE_0_ADDRESS + 4 * 32 + 6) 	; set the vram address (and place the text on the fifth line at x location 6)
	assign_16i text_address, title_text 					; put the text in the address
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
 
.proc display_game_screen
	jsr ppu_off
	jsr clear_nametable

	vram_set_address (NAME_TABLE_0_ADDRESS + 22 * 32) 	; set the address of the vram on the start of the 23rd line
	assign_16i paddr, game_screen_mountain 				; store the pointer to the mountain game screen
	ldy #0
	@loop: 				; loop over all the mountains
		lda (paddr),y
		sta PPU_VRAM_IO
		iny 
		cpy #$20
		bne @loop

	vram_set_address (NAME_TABLE_0_ADDRESS + 26 * 32) ; set the address of the vram on the start of the 26th line
	ldy #0
	lda #9 		; line character
	@loop2: 		; draw a full line
		sta PPU_VRAM_IO
		iny 
		cpy #$20
		bne @loop2

	assign_16i paddr, game_screen_scoreline 	; store pointer to score line text
	ldy #0
	@loop3: 				; send it all to the register
		lda (paddr),y
		sta PPU_VRAM_IO
		iny 
		cpy #$d
		bne @loop3

	jsr ppu_update
	rts 
.endproc

.proc player_actions
	lda player_dead    
	beq @continue
	cmp #1 		; player flagged as dead, set initial shape
	bne @notstep1
	ldx #20 	; set 1st explosion pattern
	jsr set_player_shape
	lda #1 		; select 2nd palette
	sta oam + 2
	sta oam + 6
	sta oam + 10
	sta oam + 14
	jmp @nextstep

	@notstep1:
		cmp #5 	; ready to change to next explosion shape
		bne @notstep2
		ldx #24 ; set 2nd explosion pattern
		jsr set_player_shape
		jmp @nextstep

	@notstep2:
		cmp #10 ; ready to change to next explosion shape
		bne @notstep3
		ldx #28 ; set 3rd explosion pattern
		jsr set_player_shape
		jmp @nextstep

	@notstep3:
		cmp #15 ; ready to change to next explosion shape
		bne @notstep4
		ldx #32 ; set 3rd explosion pattern
		jsr set_player_shape
		jmp @nextstep

	@notstep4:
		cmp #20 ; explosion finished, reset player
		bne @nextstep
		lda lives
		cmp #0 	; check for game over
		bne @notgameover
		rts 	; game over exit

	@notgameover:
		jsr setup_level 	; reset all enemies objects
		jsr display_player 	; display the player at the starting position
		lda #0 				; clear the player dead flag
		sta player_dead
		rts 

	@nextstep:
		inc player_dead
		rts 

	@continue:
		jsr gamepad_poll
		
		lda gamepad
		and #PAD_L
		beq not_gamepad_left
		; game pad has been pressed left
		lda oam + 3 ; get current x of ship
		cmp #0
		beq not_gamepad_left
			; subtract 1 from the ship position
			sec 
			sbc #2
			; update the four sprites that make up the ship
			sta oam + 3
			sta oam + 11
			clc 
			adc #8
			sta oam + 7
			sta oam + 15
		not_gamepad_left:

		lda gamepad
		and #PAD_R
		beq not_gamepad_right
		; gamepad has been pressed right
		lda oam + 3 ; get current X of ship
		clc 
		adc #12 ; allow with width of ship
		cmp #$fd
		beq not_gamepad_right
			lda oam + 3 ; get current X of ship
			clc 
			adc #2
			; update the four sprites that make up the ship
			sta oam + 3
			sta oam + 11
			clc 
			adc #8
			sta oam + 7
			sta oam + 15
		not_gamepad_right:

		lda gamepad
		and #PAD_A
		beq not_gamepad_a
		; gamepad A button has been pressed
		lda oam + 16 ; get Y of player bullet
		cmp #$ff ; see if the sprite is not in use
		bne not_gamepad_a
			; sprite is available, place bullet
			lda #$c0
			sta oam + 16 ; set bullet Y
			lda #4
			sta oam + 17 ; set sprite pattern 4
			lda #0
			sta oam + 18 ; set attributes
			lda oam + 3 ; get player X position
			clc
			adc #6 ; centre bullet on player
			sta oam + 19 ; set bullet X position
	not_gamepad_a:

	rts 
.endproc

.proc move_player_bullet
	lda oam + 16 		; get the current y coord
	cmp #$ff 			; see if it's in use
	beq @exit 			; if not, skip the rest of the code
		sec 
		sbc #4 			; move the bullet up by 4
		sta oam + 16 	; apply the new bullet's location
		bcs @exit 		; check if it's below 0
		lda #$ff 		; load the delete value
		sta oam + 16 	; store it in the bullet
	@exit:    
	rts   				; return from subroutine
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

.proc spawn_enemies
	ldx enemycooldown	; get the enemy cooldown
	dex 				; decrement it
	stx enemycooldown	; store it

	cpx #0 				; see if the cooldown hit 0
	beq :+ 				; if it hasnt, return from the subroutine
		rts 
	: ; if it has reached 0

	ldx #1 				; set a short cooldown (if our random value doesnt make an enemy appear, it will try again in a second)
	stx enemycooldown
	lda level 			; get the current level
	clc 				; clear the carry
	adc #1 				; add 1 to a
	asl 				; multiply by 4
	asl 
	sta temp 			; save our value
	jsr rand 			; get new random value
	tay 				; put it in the y register
	cpy temp 			; compare it to the old value
	bcc :+ 				; if it is bigger than our calculated value
		rts 			; return from subroutine
	: 					; else continue (why tf would they do this)

	ldx #20 			; set new cooldown
	stx enemycooldown

	ldy #0
	@loop: 					; loop through all enemies to find one that isnt spawned yet
		lda enemydata, y 	; if all 10 enemies are already on the screen, exit
		beq :+
			iny 
			cpy #10
			bne @loop
			rts 
		:

	lda #1 					; mark the enemy as in use
	sta enemydata, y

	tya 	; transfer current sprite index to a
	asl 	; multiply is by 16
	asl 	; because each enemy takes up 4 sprites
	asl 	; and each sprite takes 4 bytes
	asl 
	clc 
	adc #20 ; add 20 because the first 20 bytes are for the ship and the bullet
	tax 	; store it in x

	lda #0 	; set the y position as 0
	sta oam, x
	sta oam + 4, x
	lda #8
	sta oam + 8, x
	sta oam + 12, x

	lda #8 		; set the index number of the sprite
	sta oam + 1, x
	clc 
	adc #1
	sta oam + 5, x
	adc #1
	sta oam + 9, x
	adc #1
	sta oam + 13, x

	lda #%00000000 	; set the sprite attributes
	sta oam + 2, x
	sta oam + 6, x
	sta oam + 10, x
	sta oam + 14, x

	jsr rand 		; set the x coord as a random value
	and #%11110000
	clc 
	adc #48
	sta oam + 3, x
	sta oam + 11, x
	clc 
	adc #8
	sta oam + 7, x
	sta oam + 15, x

	rts 
.endproc

.proc move_enemies
	; store the bullet's information
	lda oam + 16 
	sta cy1
	lda oam + 19
	sta cx1
	lda #4
	sta ch1
	lda #1
	sta cw1

	ldy #0
	lda #0
	@loop:
		lda enemydata, y
		bne :+ 			; check if the enemy is on the screen
			jmp @skip
		:         

		tya 	; calculate the position in the oam table
		asl 	; once again multiply by 16 because
		asl 	; 1 enemy = 4 sprites
		asl 	; 1 sprite = 4 bytes
		asl 
		clc 
		adc #20 ; add 20 to skip the first 5 sprites
		tax 	; store the position in x

		lda oam, x 			; load current y position
		clc 				; clear the carry
		adc #1 				; move it down by 1
		cmp #$c4 			; check if it hit the bottom
		bcc @nohitbottom 	; if it did not, go to next section

		lda #$ff 			; put all the addresses at the maximum (to move it out the screen)
		sta oam, x
		sta oam + 4, x
		sta oam + 8, x
		sta oam + 12, x

		lda #0
		sta enemydata, y 	; mark the enemy not used in the enemydata

		clc 
		lda score 			; check if score not 0
		adc score + 1
		adc score + 2
		bne :+
			jmp @skip
		:

		lda #1 				; remove 10 not 1 because we add a 0 at the end for bigger numbers(the 0 never changes)
		jsr subtract_score 	; subtract score

		jmp @skip 			; go to the end of the loop

		@nohitbottom: 		; if it did not hit the bottom
		sta oam, x 			; store the new y coord
		sta oam + 4, x
		clc 
		adc #8
		sta oam + 8, x
		sta oam + 12, x

		lda player_dead 		; check that the play aint already dead
		cmp #0
		bne @notlevelwithplayer ; jump to death screen or sum

		lda oam, x 			; get enemy y coord
		clc 
		adc #14 			; add enemy height
		cmp #$cc 			; compare to player y
		bcc @notlevelwithplayer 	; skip rest of collision checking if enemy is still above player

		lda oam + 3 		; load player x coord
		clc 
		adc #12 			; add player width
		cmp oam + 3, x 		; compare to enemy x coord
		bcc @notlevelwithplayer ; if enemy is to the right of that coord skip the rest (no collision)

		lda oam + 3, x 		; same check but inversed
		clc 
		adc #14
		cmp oam + 3
		bcc @notlevelwithplayer ; jump if no collision
		
		dec lives 			; at this point there is a collision and we decrement the current lives --------------------------------------------------------------------------------does the player die after 1 hit?
		lda #%00000100 		; set current flag for lives to be displayed
		ora update
		sta update
		lda #1 				; marks player as dead
		sta player_dead

		lda #$ff 			; erase the enemy
		sta oam , x
		sta oam + 4 , x
		sta oam + 8 , x
		sta oam + 12 , x
		lda #0
		sta enemydata,y
		jmp @skip 			; enemy gone so no need to move it further

		@notlevelwithplayer:

		lda oam + $10 		; check if the bullet is on the screen
		cmp #$ff
		beq @skip

		lda oam , x 		; store the current enemy location
		sta cy2
		lda oam+3,x
		sta cx2
		lda #14
		sta cw2
		sta ch2

		jsr collision_test  ;do the collision test with current enemy
		bcc @skip           ;if carry flag is clear (no collision), skip the rest
		lda #$ff            ;else move enemies off the map
		sta oam+16
		sta oam,x
		sta oam+4,x
		sta oam+8,x
		sta oam+12,x

		lda #0
		sta enemydata,y     ;and mark it as deleted

		lda #2        ;add 20 (not 2 because we add a 0 to the end to make the numbers look bigger )to the score
		jsr add_score ;yes
		@skip:
		iny       ;increment the enemy counter for the loop
		cpy #10   ;check if we have gone through all the enemies
		beq :+
			jmp @loop
		:
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

.proc set_player_shape ;change player pattern table
	stx oam+1
	inx
	stx oam+5
	inx
	stx oam+9
	inx
	stx oam+13
	rts
.endproc

.proc display_player
 lda #196
 sta oam
 sta oam+4
 lda #204
 sta oam+8
 sta oam+12

 ldx #0
 stx oam+1
 inx
 stx oam+5
 inx
 stx oam+9
 inx
 stx oam+13

 lda #%00000000
 sta oam+2
 sta oam+6
 sta oam+10
 sta oam+14

 lda #120
 sta oam+3
 sta oam+11
 lda #128
 sta oam+7
 sta oam+15
 rts
.endproc

.proc setup_level 	
	lda #0 ; clear enemy data
	ldx #0
	@loop:
		sta enemydata,x
		inx
		cpx #10
		bne @loop
		lda #20 ; set initial enemy cool down
		sta enemycooldown
		
		lda #$ff ; hide all enemy sprites
		ldx #0
	@loop2:
		sta oam+20,x
		inx
		cpx #160
		bne @loop2
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

.proc display_lives
	vram_set_address (NAME_TABLE_0_ADDRESS + 27 * 32 + 14)
	ldx lives
	beq @skip ; no lives to display
	and #%00000111 ; limit to a max of 8
	@loop:
		lda #5
		sta PPU_VRAM_IO
		lda #6
		sta PPU_VRAM_IO
		dex
		bne @loop

	@skip:
		lda #8 ; blank out the remainder of the row
		sec
		sbc lives
		bcc @skip2
		tax
		lda #0
	@loop2:
		sta PPU_VRAM_IO
		sta PPU_VRAM_IO
		dex
		bne @loop2
	@skip2:

		vram_set_address (NAME_TABLE_0_ADDRESS + 28 * 32 + 14)
		ldx lives
		beq @skip3 ; no lives to display
		and #%00000111 ; limit to a max of 8
	@loop3:
		lda #7
		sta PPU_VRAM_IO
		lda #8
		sta PPU_VRAM_IO
		dex
		bne @loop3	

	@skip3:
		lda #8 ; blank out the remainder of the row
		sec
		sbc lives
		bcc @skip4
		tax
		lda #0
	@loop4:
		sta PPU_VRAM_IO
		sta PPU_VRAM_IO
		dex
		bne @loop4
	@skip4:

	rts
.endproc

title_text:
	.byte "M E G A B L A S T",0

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
 

	game_screen_mountain:
	.byte 001,002,003,004,001,002,003,004,001,002,003,004,001,002,003,004
	.byte 001,002,003,004,001,002,003,004,001,002,003,004,001,002,003,004

	game_screen_scoreline:
		.byte "SCORE 0000000"
	
	ship_projectile:
		.byte 009
