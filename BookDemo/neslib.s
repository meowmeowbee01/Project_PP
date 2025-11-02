;******************************************************************
; neslib.s: NES Function Library
;******************************************************************
; Define PPU Registers
PPU_CONTROL = $2000         ;write
PPU_MASK = $2001            ;write
PPU_STATUS = $2002          ;read
PPU_SPRRAM_ADDRESS = $2003  ;write
PPU_SPRRAM_IO = $2004       ;write
PPU_VRAM_ADDRESS1 = $2005   ;write
PPU_VRAM_ADDRESS2 = $2006   ;write
PPU_VRAM_IO = $2007         ;write/read
SPRITE_DMA = $4014          ;dma register

;nametable locations
NT_2000 = $00 
NT_2400 = $01   
NT_2800 = $02
NT_2C00 = $03

;vram pointer increment
VRAM_DOWN = $04

OBJ_0000 = $00
OBJ_1000 = $08
OBJ_8X16 = $20

BG_0000 = $00 ;
BG_1000 = $10

;enables nmi
VBLANK_NMI = $80

;background settings
BG_OFF = $00    ;off
BG_CLIP = $08   ;clip
BG_ON = $0A     ;on

;object settings
OBJ_OFF = $00   ;off
OBJ_CLIP = $10  ;clip
OBJ_ON = $14    ;on

;apu addresses
APU_DM_CONTROL = $4010
APU_CLOCK = $4015

; Joystick/Controller values
JOYPAD1 = $4016
JOYPAD2 = $4017

; Gamepad bit values
PAD_A = $01
PAD_B = $02
PAD_SELECT = $04
PAD_START = $08
PAD_U = $10
PAD_D = $20
PAD_L = $40
PAD_R = $80

;useful addresses
NAME_TABLE_0_ADDRESS = $2000
ATTRIBUTE_TABLE_0_ADDRESS = $23C0
NAME_TABLE_1_ADDRESS = $2400
ATTRIBUTE_TABLE_1_ADDRESS = $27C0

.segment "ZEROPAGE"
    nmi_ready: .res 1

    ppu_ctl0: .res 1
    ppu_ctl1: .res 1 
    gamepad: .res 1 
    text_address: .res 2

    ;object 1
    cx1: .res 1 ;x coord
    cy1: .res 1 ;y coord
    cw1: .res 1 ;width
    ch1: .res 1 ;height

    ;object 2
    cx2: .res 1 ;x coord
    cy2: .res 1 ;y coord
    cw2: .res 1 ;width
    ch2: .res 1 ;height

    .include "macro.s"

.segment "CODE"
    .proc wait_frame    ;sets nmi flag and waits until it's reset
        inc nmi_ready   ;increments whatever's in nmi_ready
        @loop:
            lda nmi_ready   ;gets current nmi_ready state
            bne @loop       ;loops if not 0
        rts     ;return from subroutine
    .endproc

    .proc ppu_update    ;wait until next nmi and turn rendering on
        lda ppu_ctl0    ;load first ppu control register value
        ora #VBLANK_NMI ;enable the nmi
        sta ppu_ctl0    ;store it back in the ppu control register variable
        sta PPU_CONTROL ;store it in the ppu control register
        lda ppu_ctl1    ;get second ppu control variable value
        ora #OBJ_ON|BG_ON   ;enable objects and sprites
        sta ppu_ctl1        ;store it back in the second ppu control variable
        jsr wait_frame      ;go to wait frame
        rts                 ;return from subroutine
    .endproc

    .proc ppu_off   ;waits for ppu and then turns rendering off
        jsr wait_frame  ;wait a frame
        lda ppu_ctl0    ;load first ppu control variable
        and #%01111111  ;turn off the renderer
        sta ppu_ctl0    ;write it back to the variable
        sta PPU_CONTROL ;write it back to the ppu control address
        lda ppu_ctl1    ;get second state
        and #%11100001  ;disable all sprites/backgrounds related things
        sta ppu_ctl1    ;store it back
        sta PPU_MASK    ;store it in the ppu_mask address
        rts             ;return from subroutine
    .endproc

    .proc clear_nametable
        lda PPU_STATUS          ;get sprite data
        lda #$20                ;set the ppu address
        sta PPU_VRAM_ADDRESS2
        lda #$00
        sta PPU_VRAM_ADDRESS2

        lda #0 
        ldy #30
        rowloop:  ;empty nametable
            ldx #32
            columnloop: 
            sta PPU_VRAM_IO ;clear current byte
            dex
            bne columnloop ;loop until x is 0
            dey
            bne rowloop ;loop until y is 0

        ldx #64
        loop: ;empty attribute table
            sta PPU_VRAM_IO
            dex
            bne loop ;loop until x is 0 
        rts
    .endproc 
    .proc gamepad_poll
        lda #1      ;this tells the gamepad to send over the info
        sta JOYPAD1
        lda #0
        sta JOYPAD1

        ldx #8   ;loops 8 times to get all 8 bits of info
        loop:
            pha     ;pushes current bit onto the stack
            lda JOYPAD1

            and #%00000011  ;combines low 2 bits and stores it in carry bit
            cmp #%00000001  
            pla             ;gets the value from the stack

            ror             ;rotates the carry bit in the current value (from the right)
            dex
            bne loop
        sta gamepad
        rts
    .endproc

    .proc write_text
        ldy #0
        loop:
            lda (text_address),y    ;get current text byte (2 bytes address)
            beq exit                ;if it's 0, exit
            sta PPU_VRAM_IO         ;write it to the ppu io register
            iny                     ;increment y
            jmp loop                ;loop again
        exit:
            rts                     ;return from subroutine
    .endproc

    .proc collision_test
        clc
        lda cx1 ;get object 1 x
        adc cw1 ;add the width
        cmp cx2 ;compare to object 2 x coord
        bcc @exit   ;if the second coord is to the right of it (bigger than or equal) there's no collision

        
        clc         ;we now do the inverse
        lda cx2     ;get object 2 x
        adc cw2     ;add width to it
        cmp cx1     ;compare it to object 1 x coord
        bcc @exit   ;if object 1 is to the right of that coord, there's no collision

        lda cy1     ;no we do the same for the y coords
        adc ch1
        cmp cy2
        bcc @exit

        clc
        lda cy2
        adc ch2
        cmp cy1
        bcc @exit

        sec ;set carry flag as there is a collision
        rts ;return
        @exit:
        clc ;clear carry flag as there is no collision
        rts ;return
    .endproc

    .proc dec99_to_bytes
        ;x will extract the value x0 (x * 10)
        ;a will contain the value 0a (a * 1)
        ldx #0
        cmp #50     ;compare a to 50
        bcc try20   ;if a is smaller than 50, go to 20 check
        sbc #50     ;subtract 50
        ldx #5      ;load 5 in x
        bne try20   ;if its not 0, go to 20 check

        div20:
            inx         ;add 2 to x
            inx
            sbc #20     ;remove 20

        try20:
            cmp #20     ;compare to 20
            bcs div20   ;if it's bigger or equal to 20 go to remove 20
        try10:
            cmp #10     ;compare to 10
            bcc @finished   ;if its smaller than 10 calculation is finished
            sbc #10         ;otherwise, remove 10 and increment x
            inx
        @finished:
        rts
    .endproc

    .proc clear_sprites
        ;
        lda #255
        ldx #0
        clear_oam:
        sta oam,x
        inx
        inx
        inx
        inx
        bne clear_oam
        rts
    .endproc