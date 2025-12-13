# Retro Console Programming 
# 'Project_PP' made by Project_PP

# We are:
# Yannick RUIJTER
# Arno BUYCKX
# Ismail AKÇEKAYA
# Dan RUNISKOVS
# Liam MAAS

We provide a way to display presentation slides using NES hardware
You must put the desired text to display in content.txt
Spaces ' ' and tabs are recognised too
To separate slides, use '\s' in content.txt

To display your slides: 
	- build the game with the desired content
	- put the build .nes file in the cartidge
	- put the cartidge in the NES
	- play it!
	- press A or 'Right' on D-Pad to scroll to next slide ( repeat to cancel animation )
	- press B or 'Left' od D-Pad to scroll back to previous slide ( repeat to cancel )
	- enjoy
	
To see more options and possibilites, take a look at settingd.s

PS the first character after a slide seperator is assumed to be a newline and is therefore ignored

### escape sequences

-   "\s" can be used to indicate a slide seperator
-   "\t" can be used to insert a tab
-   "\\\\" can be used to insert a \
-   escape characters can be configured in settings.s