.macro vram_set_address newaddress
    lda PPU_STATUS          ;load ppu status
    lda #>newaddress        ;store first high and then low byte into the register for the ppu
    sta PPU_VRAM_ADDRESS2   
    lda #<newaddress
    sta PPU_VRAM_ADDRESS2
.endmacro

.macro assign_16i dest, value
    lda #<value ;puts first the low byte then high byte in destination
    sta dest+0
    lda #>value
    sta dest+1
.endmacro

.macro vram_clear_address
    lda #0                  ;clears the address
    sta PPU_VRAM_ADDRESS2
    sta PPU_VRAM_ADDRESS2
.endmacro