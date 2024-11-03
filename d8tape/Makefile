#
#	makefile for d8tape
#
#	(C) Copyright 2001, 2003, 2007, by Robert Krten, all rights reserved.
#	Please see the LICENSE file for more information.
#
#	I collect PDP systems of almost all shapes and sizes; send me an
#	email to "rk@parse.com" if you have one to give away, sell,
#	or trade, or visit the museum at http://www.parse.com/~museum/
#
#	2001 01 07	R. Krten		created
#	2007 10 25	R. Krten		added flow module
#	2015 01 18	D. North		updated test routines
#
#	The "bm" utility in the "core:" target simply increments
#	the version number -- you can comment out that line with
#	no ill effects, or simply "ln /bin/true /usr/local/bin/bm"
#	(or similar) to nullify its effects.
#

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

DEBUG = -g2
OBJECTS = main.o dasm.o flow.o

CFLAGS = $(DEBUG) -Wall -Wno-unused-function
LDFLAGS = $(DEBUG)

COMMON = Makefile

all:   d8tape

d8tape: $(OBJECTS) $(COMMON)
	cc $(CFLAGS) -o d8tape $(OBJECTS) version.c $(LDFLAGS)

main.o:	main.c d8tape.h

flow.o:	flow.c d8tape.h

dasm.o:	dasm.c d8tape.h iot.h

install:
	cp -v -p d8tape$(EXE) $(BINDIR)

release:
	make clean
	tar cvf d8tape.tar Makefile *.c *.h LICENSE

test:
	macro8x -d -x -m -u test.pal
	./d8tape test.bin | expand -4 > test.list
	cp test.list verify.pal
	macro8x -d -x -m -u verify.pal
	dumpbin8x.pl test.bin > test.dump
	dumpbin8x.pl verify.bin > verify.dump
	-diff -s test.dump verify.dump
	./d8tape verify.bin | expand -4 > verify.list
	-diff -s test.list verify.list

clean:
	rm -f *.o d8tape.exe
	rm -f *.lst *.bin *.err *.list *.dump verify.pal

# the end
