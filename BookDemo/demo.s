
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
  paddr: .res 2 
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

  jsr ppu_update

  titleloop:      ;loops until either one of the following 4 buttons was pressed
    jsr gamepad_poll
    lda gamepad
    and #PAD_A|PAD_B|PAD_START|PAD_SELECT
    beq titleloop

  jsr display_game_screen 
  mainloop:
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
    cpy #$20
    bne loop3

  jsr ppu_update
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
