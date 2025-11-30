INPUT_COOLDOWN = 15 				; frames

SCROLL_SPEED = 2
TAB_WIDTH = 4 						; choose width of tab in slides
PADDING_TOP = 2 					; number of lines from the top that are left blank (preferably min 1)
PADDING_LEFT = 2 					; number of colums left blank at the left side
; 0, 1, 2, 3 = red, green, blue, white
palettes: .byte 0, 1, 2, 3, 3, 3, 1 ; putting less indices than slides results in UB
images: .byte 2, 2 					; define the dimensions of the images (first width than height)

ESCAPE_CHAR = '\'
SLIDE_SEPERATOR = 's'
IMAGE_OPERATOR = 'i'
TAB_CHAR = 't'

SLIDE_INDEX_ADDR = NAME_TABLE_0_ADDRESS + (28 * 32) + 28