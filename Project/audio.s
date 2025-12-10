	; uses pulse channel 1 only. (square wave 1)
	; audio_init: 			call once in reset
	; audio_update: 		call every NMI
	; audio_play_next: 		high beep (~0.5 s)
	; audio_play_prev: 		low beep  (~0.5 s)

;.include "neslib.s" 		; for APU_CLOCK, APU_DM_CONTROL

.segment "ZEROPAGE"
	boop_timer: .res 1

.segment "CODE"
	.proc audio_init
		; enable pulse1, pulse2, triangle, noise (DMC off)
		lda #%00001111
		sta APU_CLOCK

		; disable DMC IRQ
		lda #0
		sta APU_DM_CONTROL

		lda #0
		sta $4000 				; volume 0 = mute

		lda #0
		sta boop_timer
		rts 
	.endproc

	.proc audio_update
		lda boop_timer
		beq done
			dec boop_timer
			bne done
				; timer just reached 0: silence pulse 1
				lda #0
				sta $4000
		done:
			rts 
	.endproc

	.proc audio_play_next 		; high-pitch boop
		;save_registers
		lda #$1e 				; 30 frames
		sta boop_timer 			; ~0.5 s at 60 FPS

		; duty 01 (25%), const volume=10
		; duty -> wavelength
		; bits: 7–6 duty, 5 loop env, 4 const vol, 3–0 volume
		lda #%01011010 			; duty=01, const, vol=10
		sta $4000

		; set up pulse 1: sweep off, long length, silent
		lda #0
		sta $4001 				; disable sweep
		lda #%11111000 			; lda #f8 -> upper timer bits(0-2) -> 0
		sta $4003 				; long length counter, hi period bits = 0

		lda #$64 				; low period -> higher pitch (=100)
		sta $4002 				; fine period bits (hi bits stay 0 from init)
		;restore_regsiters
		rts 
	.endproc

	.proc audio_play_prev 		; low-pitch boop
		;save_registers
		lda #$1e 				; 30 frames
		sta boop_timer

		lda #%01011010 			; same envelope, same channel
		sta $4000

		; set up pulse 1: sweep off, long length, silent
		lda #0
		sta $4001 				; disable sweep
		lda #%11111000 			; lda #f8 -> upper timer bits(0-2) -> 0
		sta $4003 				; long length counter, hi period bits = 0

		lda #$b4 				; bigger period -> lower pitch (=180)
		sta $4002
		;restore_regsiters
		rts 
	.endproc