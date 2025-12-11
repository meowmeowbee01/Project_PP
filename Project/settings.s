; input settings
	INPUT_COOLDOWN = 15 		; frames

; slide settings
	; slide transition animation
		SCROLL_SPEED = 5

	; padding
		PADDING_TOP = 1 		; number of lines from the top that are left blank (preferably min 1)
		PADDING_BOTTOM = 1 		; number of lines from the bottom that are left blank (preferably min 1)
		PADDING_LEFT = 1 		; number of colums left blank at the left side
		PADDING_RIGHT = 1 		; number of colums left blank at the right side

	; slide index indicator (e.g.: 5/10)
		; 0,0 = top left
		INDEX_X_POS = 27 		; in case of single digits, cap at 29
		INDEX_Y_POS = 28
		INDEX_SEPERATOR = '/'

	; character displayment
		TAB_WIDTH = 4 			; choose display width of tabs in slides

	; colors
		; 0, 1, 2, 3 = red, green, blue, white
		palettes: .byte 0,1,2,3,0,1,2,3 	; putting less indices than slides results in UB (putting more will correctly be ignored)

; escape characters
	ESCAPE_CHAR = '\'
	SLIDE_SEPERATOR = 's'
	TAB_CHAR = 't'