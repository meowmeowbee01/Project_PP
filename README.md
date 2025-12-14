# Project_PP

### Made by:

-   Yannick Ruijter
-   Arno Buyckx
-   Ismail Akçekaya
-   Dan Runiskovs
-   Liam Maas (emotional support)

## Introduction

We provide a way to display presentation slides using NES hardware

You must put the desired text to display in `content.txt`.
currently there is no way to change the content after assembly

Some settings related to input and display can be changed in `settings.s`

## how to build

-   edit `content.txt` and `settings.s`
-   assemble main.s with the ca65 assembler
-   use the ld65 linker to create a .nes file
-   put the .nes file on a NES cartidge
-   put the cartidge in the NES
-   play it!

## how to use

-   use a standard controller in port 1
-   (optional) use the light gun in port 2

next slide:

-   A button
-   right D-pad
-   shoot the light gun

previous slide:

-   B button
-   left D-pad

skipping animations:

-   press any input to skip an animation

## content.txt

-   any text in `content.txt` will be used for the slideshow
-   `content.txt` should use ASCII text encoding (UTF-8 is compatible with ASCII)
-   supported ASCII characters:
    -   all printable characters
    -   CR and LF (CRLF and LF line endings may even be mixed)
    -   TAB
    -   SPACE
-   there are also some escape sequences:
    -   `\s` can be used to indicate a slide seperator
    -   `\t` can be used to insert a `TAB`
    -   `\\` can be used to insert a `\`
-   escape characters can be configured in settings.s
-   the first character after a slide seperator is assumed to be a newline and is therefore ignored

## settings.s

-   `settings.s` is self documenting via comments
