# makefile for pdp8 support routines

# system dependencies
ifeq ($(WINDIR),)
# unix
BINDIR=../bin
EXE=
else
# cygwin
BINDIR=../exe
EXE=.exe
endif

# all the bins
BIN :=d8tape macro8x palbart
# all the scripts
SCR :=binchk dumpbin8x hex2mac rx02_image_dump config11 diffrom enet2hex img2sdcard simhtape

all:		$(BIN)
		for DIR in $^ ; do cd $$DIR && $(MAKE) $@ ; cd .. ; done

clean:		$(BIN)
		for DIR in $^ ; do cd $$DIR && $(MAKE) $@ ; cd .. ; done

install::	$(BIN)
		for DIR in $^ ; do cd $$DIR && $(MAKE) $@ ; cd .. ; done

install::	$(SCR)
		for DIR in $^ ; do cp -v -p $$DIR/*.pl $(BINDIR) ; done

# the end
