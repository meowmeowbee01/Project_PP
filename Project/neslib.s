;******************************************************************
; neslib.s: NES function library
;******************************************************************

.include "macro.s"

; define PPU registers
PPU_CONTROL			= $2000		; PPU control register 1 (write)
PPU_MASK			= $2001		; PPU control register 2 (write)
PPU_STATUS			= $2002		; PPU status register (read)
PPU_SPRRAM_ADDRESS	= $2003 	; PPU SPR-RAM address register (write)
PPU_SPRRAM_IO		= $2004 	; PPU SPR-RAM I/O register (write)
PPU_VRAM_ADDRESS1	= $2005 	; PPU VRAM address register 1 (write)
PPU_VRAM_ADDRESS2	= $2006 	; PPU VRAM address register 2 (write)
PPU_VRAM_IO			= $2007 	; VRAM I/O register (read/write)
SPRITE_DMA			= $4014 	; sprite DMA register

; nametable locations
NT_2000 = 0
NT_2400 = 1
NT_2800 = $02
NT_2C00 = $03

; vram pointer increment
VRAM_DOWN = $04

OBJ_0000 = 0
OBJ_1000 = %10000000
OBJ_8X16 = %00100000

BG_0000 = 0
BG_1000 = %10010000

; enables nmi
VBLANK_NMI = %10000000

; background settings
BG_OFF 	= 0 		; off
BG_CLIP = %00001000 ; clip
BG_ON 	= %00001010	; on

; object settings
OBJ_OFF 	= 0 		;off
OBJ_CLIP 	= %00010000 ;clip
OBJ_ON 		= %00010100	;on

; APU registers
APU_DM_CONTROL 	= $4010		; APU delta modulation control register (write)
APU_CLOCK		= $4015		; APU sound/vertical clock signal register (read/write)

; joystick/controller values
JOYPAD1 = $4016		; joypad 1 (read/write)
JOYPAD2 = $4017		; joypad 2 (read/write)

; gamepad bit values
PAD_A		= %00000001
PAD_B		= %00000010
PAD_SELECT	= %00000100
PAD_START	= %00001000
PAD_UP		= %00010000
PAD_DOWN	= %00100000
PAD_LEFT	= %01000000
PAD_RIGHT	= %10000000

; useful addresses
NAME_TABLE_0_ADDRESS 		= $2000
ATTRIBUTE_TABLE_0_ADDRESS 	= $23c0
NAME_TABLE_1_ADDRESS 		= $2400
ATTRIBUTE_TABLE_1_ADDRESS 	= $27c0

.segment "ZEROPAGE"
	nmi_ready: .res 1
	ppu_ctl0: .res 1
	ppu_ctl1: .res 1 
	gamepad: .res 1 
	text_address: .res 2
	text_line: .res 1

	; object 1
	cx1: .res 1 ; x coord
	cy1: .res 1 ; y coord
	cw1: .res 1 ; width
	ch1: .res 1 ; height

	; object 2
	cx2: .res 1 ; x coord
	cy2: .res 1 ; y coord
	cw2: .res 1 ; width
	ch2: .res 1 ; height

.segment "CODE"
	.proc wait_frame 		; sets nmi flag and waits until it's reset
		inc nmi_ready 		; increments whatever's in nmi_ready
		@loop:
			lda nmi_ready 	; gets current nmi_ready state
			bne @loop 		; loops if not 0
		rts 				; return from subroutine
	.endproc

	.proc ppu_update 		; wait until next nmi and turn rendering on
		lda ppu_ctl0 		; load first ppu control register value
		ora #VBLANK_NMI 	; enable the nmi
		sta ppu_ctl0 		; store it back in the ppu control register variable
		sta PPU_CONTROL 	; store it in the ppu control register
		lda ppu_ctl1 		; get second ppu control variable value
		ora #OBJ_ON|BG_ON 	; enable objects and sprites
		sta ppu_ctl1 		; store it back in the second ppu control variable
		jsr wait_frame 		; wait a frame
		rts 				; return from subroutine
	.endproc

	.proc ppu_off 		; waits for ppu and then turns rendering off
		jsr wait_frame 	; wait a frame
		lda ppu_ctl0 	; load first ppu control variable
		and #%01111111 	; turn off the renderer
		sta ppu_ctl0 	; write it back to the variable
		sta PPU_CONTROL ; write it back to the ppu control address
		lda ppu_ctl1 	; get second state
		and #%11100001 	; disable all sprites/backgrounds related things
		sta ppu_ctl1 	; store it back
		sta PPU_MASK 	; store it in the ppu_mask address
		rts 			; return from subroutine
	.endproc

	.proc clear_nametable
		lda PPU_STATUS 		; get sprite data
		lda #$20 			; set the ppu address to $2000
		sta PPU_VRAM_ADDRESS2
		lda #0
		sta PPU_VRAM_ADDRESS2

		lda #0
		ldy #$1e
		rowloop: 				; empty nametable
			ldx #$20
			columnloop: 
				sta PPU_VRAM_IO ; clear current byte
				dex 
				bne columnloop 	; loop until x is 0
			dey 
			bne rowloop 		; loop until y is 0

		ldx #$40
		loop: 					; empty attribute table
			sta PPU_VRAM_IO
			dex 
			bne loop 			; loop until x is 0 
		rts 
	.endproc

	.proc gamepad_poll
		lda #1 				; this tells the gamepad to send over the info
		sta JOYPAD1
		lda #0
		sta JOYPAD1

		ldx #$8 			; loops 8 times to get all 8 bits of info
		loop:
			pha 			; pushes current bit onto the stack
			lda JOYPAD1

			and #%00000011 	; combines low 2 bits and stores it in carry bit
			cmp #%00000001  
			pla 			; gets the value from the stack

			ror 			; rotates the carry bit in the current value (from the right)
			dex 
			bne loop
		sta gamepad
		rts 
	.endproc

	.proc write_text
		ldy #0
		loop:
			lda (text_address),y 	; get current text byte (2 bytes address)
			beq exit 				; if it's 0, exit
			; if its $a go to a new line
			cmp #$a
			bne skipnewline
				inc text_line
				lda PPU_STATUS 					; load ppu status
				lda #>NAME_TABLE_0_ADDRESS 		; store first high and then low byte into the register for the ppu
				sta PPU_VRAM_ADDRESS2   
				lda text_line
				asl 
				asl 
				asl 
				asl 
				asl 
				sec 
				sbc #1
				clc 
				adc #<NAME_TABLE_0_ADDRESS
				sta PPU_VRAM_ADDRESS2
			skipnewline:
			sta PPU_VRAM_IO 		; write it to the ppu io register
			iny 					; increment y
			jmp loop 				; loop again
		exit:
			rts 					; return from subroutine
	.endproc

	.proc clear_sprites
		lda #$ff
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