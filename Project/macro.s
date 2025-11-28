.macro vram_set_address newaddress
	lda PPU_STATUS 			; load ppu status
	lda #>newaddress 		; store first high and then low byte into the register for the ppu
	sta PPU_VRAM_ADDRESS
	lda #<newaddress
	sta PPU_VRAM_ADDRESS
.endmacro

.macro assign_16i dest, value
	lda #<value 			; puts first the low byte then high byte in destination (+1)
	sta dest + 0
	lda #>value
	sta dest + 1
.endmacro

.macro vram_clear_address
	lda #0 					; clears the address
	sta PPU_VRAM_ADDRESS
	sta PPU_VRAM_ADDRESS
.endmacro

.macro save_registers
	pha 
	txa 
	pha 
	tya 
	pha 
.endmacro

.macro restore_regsiters
	pla 
	tay 
	pla 
	tax 
	pla 
.endmacro

.macro clear_nametable vram_address
	vram_set_address(vram_address)
	jsr clear_nametable
.endmacro

.macro increment_16i_pointer pointer
	clc 
	lda pointer
	adc #1
	sta pointer
	lda pointer + 1
	adc #0
	sta pointer + 1
.endmacro