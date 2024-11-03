# makefile for pdp support routines

# system dependencies
ifeq ($(MAKE_HOST),x86_64-pc-cygwin)
  # cygwin 64b
  BINDIR=../exe64
  EXE=.exe
else ifeq ($(MAKE_HOST),i686-pc-cygwin)
  # cygwin 32b
  BINDIR=../exe
  EXE=.exe
else
  # unix
  BINDIR=../bin
  EXE=
endif

# all the bins
BIN :=d8tape lbn2pbn macro8x palbart
# all the scripts
SCR :=binchk config11 diffrom dumpbin8x enet2hex hex2mac img2sdcard rx_image_dump simhtape

all:		$(BIN)
		for DIR in $^ ; do cd $$DIR && $(MAKE) $@ ; cd .. ; done

clean:		$(BIN)
		for DIR in $^ ; do cd $$DIR && $(MAKE) $@ ; cd .. ; done

install::	$(BIN)
		for DIR in $^ ; do cd $$DIR && $(MAKE) $@ ; cd .. ; done

install::	$(SCR)
		for DIR in $^ ; do cp -v -p $$DIR/*.pl $(BINDIR) ; done

test::
		@echo MAKE_HOST=$(MAKE_HOST)
		@echo BINDIR=$(BINDIR)
		@echo EXE=$(EXE)

# the end
