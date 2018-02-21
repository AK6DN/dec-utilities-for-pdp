# makefile for pdp8 support routines

# system dependencies
ifeq ($(WINDIR),)
# unix
BINDIR=../../bin
EXE=
else
# cygwin
BINDIR=../../exe
EXE=.exe
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
BIN=macro8x$(EXE)

all:		$(BIN)

clean:
		rm -f $(BIN)

install:
		cp $(BIN) $(BINDIR)

# make the macro8x binary
macro8x$(EXE):	macro8x.c
		$(CC) $(CFLAGS) $(LFLAGS) $(LIBS) -o $@ $<

# the end
