INPUT_COOLDOWN = 15 	            ; frames

TAB_WIDTH = 4                       ; choose width of tab in slides
PADDING_TOP = 12                    ; number of lines from the top that are left blank (preferably min 1)
PADDING_LEFT = 2                    ; number of colums left blank at the left side
; 0, 1, 2, 3 = red, green, blue, white
palettes: .byte 0, 1, 2, 3, 3, 3    ; putting less indices that slides results in UB

ESCAPE_CHAR = '\'                   
SLIDE_SEPERATOR = 's'