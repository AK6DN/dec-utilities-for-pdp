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
#
#	The "bm" utility in the "core:" target simply increments
#	the version number -- you can comment out that line with
#	no ill effects, or simply "ln /bin/true /usr/local/bin/bm"
#	(or similar) to nullify its effects.
#

DEBUG = -g2
OBJECTS = main.o dasm.o flow.o

CFLAGS = $(DEBUG) -Wall
LDFLAGS = $(DEBUG)

Common = Makefile

d8tape: $(OBJECTS)
	cc $(CFLAGS) -o d8tape $(OBJECTS) version.c $(LDFLAGS)

main.o: main.c $(Common)

install:
	make
	cp d8tape.exe ../../exe

release:
	make clean
	tar cvf d8tape.tar Makefile *.c *.h LICENSE
	gzip -9v d8tape.tar

test:
	macro8x -d -x -m -u test.pal
	d8tape test.bin | expand -4 > test.list
	cp test.list verify.pal
	macro8x -d -x -m -u verify.pal
	dumpbin8x.pl test.bin > test.dump
	dumpbin8x.pl verify.bin > verify.dump
	-diff -s test.dump verify.dump
	d8tape verify.bin | expand -4 > verify.list
	-diff -s test.list verify.list

clean:
	rm -f *.o d8tape.exe
