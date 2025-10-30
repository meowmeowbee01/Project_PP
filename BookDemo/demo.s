
.segment "HEADER"
  NES_MAPPER = 0
  NES_MIRROR = 0
  NES_SRAM = 0
  ; .byte "NES", $1A      ; iNES header identifier
  .byte "NES", $1A      ;identification
  .byte 2               ; 2x 16KB PRG code
  .byte 1               ; 1x  8KB CHR data
  .byte NES_MIRROR | (NES_SRAM << 1) | ((NES_MAPPER & $f) << 4)           ; mirror mode and sram and mapper
  .byte $00             ; mapper
  .byte $00, $00, $00, $00  ;misc things (will later add)
  .byte $00, $00, $00, $00

;*****************************************************************
; Import both the background and sprite character sets
;*****************************************************************
.segment "TILES"
  .incbin "megablast.chr"

.segment "VECTORS"
  ;; When an NMI happens (once per frame if enabled) the label nmi:
  .word nmi
  ;; When the processor first turns on or is reset, it will jump to the label reset:
  .word reset
  ;; External interrupt IRQ (unused)
  .word irq

; "nes" linker config requires a STARTUP section, even  
; if it's empty
.segment "ZEROPAGE"
  paddr: .res 2     ;pointer to 16 bit address
  time: .res 2    
  lasttime: .res 1 
  SEED0: .res 2
  SEED2: .res 2 
  level: .res 1
  animate: .res 1
  enemydata: .res 20
  enemycooldown: .res 1
  temp: .res 10
.segment "OAM"
  oam: .res 256

.include "neslib.s"

;*****************************************************************
; Remainder of normal RAM area
;*****************************************************************
.segment "BSS"
  palette: .res 32 

.segment "STARTUP"

.segment "CODE" ; Main code segment for the program

irq: ;currently nothing yet for the irq
  rti

.proc reset
  sei
  cld
  lda #0
  sta PPU_CONTROL ;disable rendering
  sta PPU_MASK 
  sta APU_DM_CONTROL
  lda #$40
  sta JOYPAD2 ;disable apu frame irq

  ldx #$FF ;init the stack
  txs

  bit PPU_STATUS
  : ;wait for vblank
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

    lda #$FF
    ldx #$00
  clear_oam:
    sta oam, x 
    inx
    inx
    inx
    inx
    bne clear_oam

    bit PPU_STATUS
  : ;wait for vblank
    bit PPU_STATUS
    bpl :-

  lda #%10001000
  sta PPU_CONTROL ;enable nmi

  jmp main
.endproc
.proc nmi
  pha  ;store registers and accumulator
  txa  ;on stack before changing it
  pha  
  tya  
  pha 

  inc time  ;increment time tick counter
  bne :+
    inc time+1
  :
  bit PPU_STATUS ;transfer oam data using dma
  lda #>oam
  sta SPRITE_DMA

  vram_set_address $3F00
  ldx #$00
  @loop: ;transfer the 32 bytes to vram
    lda palette, x 
    sta PPU_VRAM_IO
    inx
    cpx #$20
    bcc @loop

  lda #$00  ;reset the address
  sta PPU_VRAM_ADDRESS1
  sta PPU_VRAM_ADDRESS1
  
  lda ppu_ctl0    ;get current control variable
  sta PPU_CONTROL ;write it to the register
  lda ppu_ctl1    ;get current mask variable
  sta PPU_MASK    ;write it to the register

  ldx #$00      ;flag the nmi as ready
  stx nmi_ready

  pla ;store the original values
  tay ;back to the registers
  pla 
  tax 
  pla 
  rti
.endproc

.proc main
  ldx #0
  paletteloop: ;copy the palette from the rom into the ram area for it
    lda default_palette, x  ;load it from the rom
    sta palette, x  ;store it in the ram
    inx ;increment x
    cpx #$20 ;compare to 32
    bcc paletteloop ;if 32 is equal or bigger (thats when the carry flag gets set) loop again

  jsr display_title_screen

  lda #VBLANK_NMI | BG_0000 | OBJ_1000 ;set game settings
  sta ppu_ctl0
  lda #BG_ON | OBJ_ON
  sta ppu_ctl1

  ;set the ship's y coordinates
  lda #192
  sta oam
  sta oam+4
  lda #200
  sta oam+8
  sta oam+12

  ;set the ship's sprite index number 
  ldx #0
  stx oam+1
  inx
  stx oam+5
  inx
  stx oam+9
  inx
  stx oam+13

  ;set the sprite's attributes
  lda #%00000000
  sta oam+2
  sta oam+6
  sta oam+10
  sta oam+14

  ;set the sprite's x positions
  lda #120
  sta oam+3
  sta oam+11
  lda #128
  sta oam+7
  sta oam+15

  jsr ppu_update


  titleloop:      ;loops until either one of the following 4 buttons was pressed
    jsr gamepad_poll
    lda gamepad
    and #PAD_A|PAD_B|PAD_START|PAD_SELECT
    beq titleloop
    
  ;dont ask questions about this part of the code (only god knows why)
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

  lda #1    ;set current level to 1
  sta level
  jsr setup_level 

  jsr display_game_screen 
  mainloop:
    lda time      ;get current tick counter

    cmp lasttime  ;compare it to the previous one
    beq mainloop  ;if no time has passed, keep looping

    sta lasttime  ;store the current time in the last time 
    jsr player_actions
    jsr move_player_bullet
    jsr spawn_enemies
    jsr move_enemies
    jmp mainloop
      
.endproc

.proc display_title_screen
  jsr ppu_off         ;turn rendering off
  jsr clear_nametable ;clear nametable

  vram_set_address (NAME_TABLE_0_ADDRESS + 4 * 32 + 6) ;set the vram address (and place the text on the fifth line at x location 6)
  assign_16i text_address, title_text                  ;put the text in the address
  jsr write_text                                       ;write text

  vram_set_address (NAME_TABLE_0_ADDRESS + 20 * 32 + 6);set next vram address (and place the text on the 21st line at x location 6)
  assign_16i text_address, press_play_text             ;put the second text in the address
  jsr write_text                                       ;write second text

  vram_set_address (ATTRIBUTE_TABLE_0_ADDRESS + 8)     ;sets the title text to use the second palette
  assign_16i paddr, title_attributes                  

  ldy #0
  loop:           ;write all attributes to the vram
    lda (paddr),y
    sta PPU_VRAM_IO
    iny
    cpy #8
    bne loop

  jsr ppu_update  ;update the ppu
  rts
.endproc
 
.proc display_game_screen
  jsr ppu_off
  jsr clear_nametable

  vram_set_address (NAME_TABLE_0_ADDRESS + 22 * 32) ;set the address of the vram on the start of the 23rd line
  assign_16i paddr, game_screen_mountain            ;store the pointer to the mountain game screen
  ldy #0
  loop:                ;loop over all the mountains
    lda (paddr),y
    sta PPU_VRAM_IO
    iny
    cpy #$20
    bne loop

  vram_set_address (NAME_TABLE_0_ADDRESS + 26 * 32) ;set the address of the vram on the start of the 26th line
  ldy #0
  lda #9    ;line character
  loop2:    ;draw a full line
    sta PPU_VRAM_IO
    iny
    cpy #$20
    bne loop2

  assign_16i paddr, game_screen_scoreline   ;store pointer to score line text
  ldy #0
  loop3:          ;send it all to the register
    lda (paddr),y
    sta PPU_VRAM_IO
    iny
    cpy #$D
    bne loop3

  jsr ppu_update
  rts
.endproc

.proc player_actions

  jsr gamepad_poll ;check the buttons currently selected
  lda gamepad

  and #PAD_L    ;if left button was pressed
  beq :+        ;if it was not pressed skip the rest of this section
  lda oam + 3   ;retrieve the current x coord
  cmp #0        ;check if it's already on the far left side
  beq :+        ;if it is, skip the rest of this section

  sec           ;set carry flag
  sbc #2        ;move ship left by 2

  ;save the moved ship's location
  sta oam + 3 
  sta oam + 11
  clc
  adc #8
  sta oam + 7
  sta oam + 15

  : ;next section of handling gamepad input
  lda gamepad           ;load the gamepad information again
  and #PAD_R            ;check if the right button was pressed
  beq :+ ;if it wasn't, skip this section

  lda oam + 3           ;get the current x location
  clc                   ;clear the carry flag
  adc #12               ;add 12 because ship is 12 pixels wide
  cmp #254            ;see if its already hitting the right wall
  beq :+                ;if it is, skip this section
  lda oam + 3           ;get the current x coord again
  clc                   ;clear carry (again why tf would the book do this)
  adc #2                ;move it right by 2

  ;save the moved ship's location
  sta oam + 3
  sta oam + 11
  clc
  adc #8
  sta oam + 7
  sta oam + 15

  :   ;end of section
  lda gamepad       ;get gamepad input again
  and #PAD_A        ;check if the a button was pressed (to fire)
  beq :+            ;if not, skip this section
  lda oam + 16      ;if it was, load the 
  cmp #$FF          ;see if the sprite is not in use yet
  bne :+            ;if it is, skip this section

  lda oam           ;get the ship's y coord
  sta oam + 16      ;make it the bullet's y coord
  lda #4            ;load sprite index 4
  sta oam + 17      ;make it the bullet's sprite index
  lda #0            ;load attributes value 0
  sta oam + 18      ;make it the bullet's attribute value
  lda oam + 3       ;get the current x coord
  clc               ;clear the carry
  adc #6            ;add 6 (so it's in the middel)
  sta oam + 19      ;make that value the bullet's x coord
  :
  rts     ;return from subroutine 
.endproc

.proc move_player_bullet
  lda oam + 16  ;get the current y coord
  cmp #$FF      ;see if it's in use
  beq @exit     ;if not, skip the rest of the code
  sec           ;set carry flag (WHY tF, IM GOING INSANE I CANT FIND A FCKING REASON WHY THISI S HERE)
  sbc #4        ;move the bullet up by 4
  sta oam + 16  ;apply the new bullet's location
  bcs @exit     ;check if it's below 0
  lda #$FF      ;load the delete value
  sta oam + 16  ;store it in the bullet
  @exit:    
  rts   ;return from subroutine
.endproc

.proc randomize ;easier rand function
  lda SEED0     ;load seed 0
  lsr           ;logical shift right
  rol SEED0+1   ;rotate left the low byte
  bcc @noeor    ;really some random shit at this point
  eor #$B4      ;yes xor it with the most random number
  @noeor:       ;i dont even know at this point
  sta SEED0     ;store the new a in the seed
  eor SEED0+1   ;another xor for more randomness
  rts
.endproc

.proc rand      ;better rand function
  jsr rand64k   ;basically do a shit ton of shifts and xor....
  jsr rand32k
  lda SEED0+1
  eor SEED2+1
  tay
  lda SEED0
  eor SEED2
  rts
.endproc

.proc rand64k
  lda SEED0+1
  asl
  asl
  eor SEED0+1
  asl
  eor SEED0+1
  asl
  asl
  eor SEED0+1
  asl
  rol SEED0
  rol SEED0+1
  rts
.endproc

.proc rand32k
  lda SEED2+1
  asl
  eor SEED2+1
  asl
  asl
  ror SEED2
  rol SEED2+1
  rts
.endproc

.proc setup_level
  lda #0
  ldx #0
  @loop:  ;clears enemy data
    sta enemydata,x
    inx
    cpx #20
    bne @loop
  lda #20           ;set initial enemy cooldown
  sta enemycooldown 
  rts
.endproc

.proc spawn_enemies
  ldx enemycooldown ;get the enemy cooldown
  dex               ;decrement it
  stx enemycooldown ;store it

  cpx #0  ;see if the cooldown hit 0
  beq :+  ;if it hasnt, return from the subroutine
  rts
  : ;if it has reached 0

  ldx #1            ;set a short cooldown (if our random value doesnt make an enemy appear, it will try again in a second)
  stx enemycooldown
  lda level         ;get the current level
  clc               ;clear the carry
  adc #1            ;add 1 to a
  asl               ;multiply by 4
  asl
  sta temp          ;save our value
  jsr rand          ;get new random value
  tay               ;put it in the y register
  cpy temp          ;compare it to the old value
  bcc :+            ;if it is bigger than our calculated value
  rts               ;return from subroutine
  :                 ;else continue (why tf would they do this)

  ldx #20           ;set new cooldown
  stx enemycooldown

  ldy #0
  @loop:            ;loop through all enemies to find one that isnt spawned yet
    lda enemydata,y ;if all 10 enemies are already on the screen, exit
    beq :+
    iny
    cpy #10
    bne @loop
  rts
  :

  lda #1          ;mark the enemy as in use
  sta enemydata,y

  tya     ;transfer current sprite index to a
  asl     ;multiply is by 16
  asl     ;because each enemy takes up 4 sprites
  asl     ;and each sprite takes 4 bytes
  asl
  clc
  adc #20 ;add 20 because the first 20 bytes are for the ship and the bullet
  tax     ;store it in x

  lda #0      ;set the y position as 0
  sta oam,x
  sta oam+4,x
  lda #8
  sta oam+8,x
  sta oam+12,x

  lda #8        ;set the index number of the sprite
  sta oam+1,x
  clc
  adc #1
  sta oam+5,x
  adc #1
  sta oam+9,x
  adc #1
  sta oam+13,x

  lda #%00000000    ;set the sprite attributes
  sta oam+2,x
  sta oam+6,x
  sta oam+10,x
  sta oam+14,x

  jsr rand        ;set the x coord as a random value
  and #%11110000
  clc
  adc #48
  sta oam+3,x
  sta oam+11,x
  clc
  adc #8
  sta oam+7,x
  sta oam+15,x

  rts
.endproc

.proc move_enemies
  ldy #0
  lda #0
  @loop:
    lda enemydata,y
    beq @skip       ;check if the enemy is on the screen  

    tya   ;calculate the position in the oam table
    asl   ;once again multiply by 16 because
    asl   ;1 enemy = 4 sprites
    asl   ;1 sprite = 4 bytes
    asl
    clc
    adc #20 ;add 20 to skip the first 5 sprites
    tax     ;store the position in x

    lda oam,x         ;load current y position
    clc               ;clear the carry
    adc #1            ;move it down by 1
    cmp #196        ;check if it hit the bottom
    bcc @nohitbottom  ;if it did not, go to next section

    lda #255    ;put all the addresses at the maximum (to move it out the screen)
    sta oam,x
    sta oam+4,x
    sta oam+8,x
    sta oam+12,x
    lda #0
    sta enemydata,y ;mark the enemy not used in the enemydata
    jmp @skip       ;go to the end of the loop

    @nohitbottom:   ;if it did not hit the bottom
    sta oam,x       ;store the new y coord
    sta oam+4,x
    clc
    adc #8
    sta oam+8,x
    sta oam+12,x
    @skip:
    iny       ;increment the enemy counter for the loop
    cpy #10   ;check if we have gone through all the enemies
    bne @loop ;if we haven't gona through all the enemies yet loop again
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
    .byte $0F,$00,$10,$30
    ;sprite palette
    .byte $0F,$28,$21,$11
    .byte $0F,$14,$24,$34
    .byte $0F,$1B,$2B,$3B
    .byte $0F,$12,$22,$32 

  game_screen_mountain:
  .byte 001,002,003,004,001,002,003,004,001,002,003,004,001,002,003,004
  .byte 001,002,003,004,001,002,003,004,001,002,003,004,001,002,003,004

  game_screen_scoreline:
    .byte "SCORE 0000000"
  
  ship_projectile:
    .byte 009
