# makefile for pdp support routines

# system dependencies
ifeq ($(MAKE_HOST),x86_64-pc-cygwin)
  # cygwin 64b
  BINDIR=../../exe64
  EXE=.exe
else ifeq ($(MAKE_HOST),i686-pc-cygwin)
  # cygwin 32b
  BINDIR=../../exe
  EXE=.exe
else
  # unix
  BINDIR=../../bin
  EXE=
endif

# omit frame pointer option needed for 25% speed improvment
OPTFLGS=-fno-strength-reduce -fomit-frame-pointer

# select compiler
CC=gcc
# cflags when making optimized version
CFLAGS=-O3 -Wall $(OPTFLGS)
# cflags when making debugging version
##CFLAGS=-g

# linker flags
LFLAGS=-lm

# system libs
LIBS=

# all the bins
BIN=lbn2pbn$(EXE)

all:	$(BIN)

clean:
	rm -f $(BIN) SRC.DSK DST.DSK SRC.RX2 DST.RX2

install:
	cp -v -p $(BIN) $(BINDIR)

# make the binary
$(BIN): lbn2pbn.c
	$(CC) $(CFLAGS) $(LFLAGS) $(LIBS) -o $@ $<

# run a test
test: $(BIN)
	cd test && test.sh

# the end
