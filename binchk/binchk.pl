#!/usr/bin/perl -w

# Copyright (c) 2005 Don North
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 
# o Redistributions of source code must retain the above copyright
#   notice, this list of conditions and the following disclaimer.
# 
# o Redistributions in binary form must reproduce the above copyright
#   notice, this list of conditions and the following disclaimer in the
#   documentation and/or other materials provided with the distribution.
# 
# o Neither the name of the copyright holder nor the names of its
#   contributors may be used to endorse or promote products derived from
#   this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# HOLDERS OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
# TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

require 5.008;

=head1 NAME

hdr - Standard template for a Perl module

=head1 SYNOPSIS

hdr
S<[--help]>
S<[--debug]>
S<[--verbose]>
S<[random arguments ...]>

=head1 DESCRIPTION

Description of the command ...

=head1 OPTIONS

The following options are available:

=over

=item B<--help>

Output this manpage and exit the program.

=item B<--debug>

Enable debug mode.

=item B<--verbose>

Verbose status reporting (not implemented).

=back

=head1 ERRORS

The following diagnostic error messages can be produced on STDERR.
The meaning should be fairly self explanatory.

C<List all the error messages here...> -- some error

=head1 EXAMPLES

Some examples of common usage:

  hdr --help

  hdr --verbose --string 'a string' --integer 5 some_other_argument

=head1 SEE ALSO

Related commands cross reference...

=head1 NOTES

Caveat emptor...

=head1 FILES

Any standard files used?

=head1 AUTHOR

Don North

=head1 HISTORY

Modification history:

  2005-05-05 v0.0 donorth - Initial version.

=cut

# options
use strict;
	
# external standard modules
use Getopt::Long;
use Pod::Text;
use FindBin;
use FileHandle;

# external local modules search path
BEGIN { unshift(@INC, $FindBin::Bin);
        unshift(@INC, $ENV{PERL5LIB}) if defined($ENV{PERL5LIB}); # cygwin bugfix
        unshift(@INC, '.'); }

# external local modules

# generic defaults
my $VERSION = 'v0.1d1'; # version of code
my $HELP = 0; # set to 1 for man page output
my $DEBUG = 0; # set to 1 for debug messages
my $VERBOSE = 0; # set to 1 for verbose messages

# specific defaults

# process command line arguments
my $NOERROR = GetOptions( "help"        => \$HELP,
			  "debug"       => \$DEBUG,
			  "verbose"     => \$VERBOSE,
			  );

# init
$VERBOSE = 1 if $DEBUG; # debug implies verbose messages

# say hello
printf STDERR "binchk.pl %s by Don North (perl %g)\n", $VERSION, $] if $VERBOSE;

# output the documentation
if ($HELP) {
    # output a man page if we can
    if (ref(Pod::Text->can('new')) eq 'CODE') {
	# try the new way if appears to exist
	my $parser = Pod::Text->new(sentence=>0, width=>78);
	printf STDOUT "\n"; $parser->parse_from_file($0);
    } else {
	# else must use the old way
	printf STDOUT "\n"; Pod::Text::pod2text(-78, $0);
    };
    exit(1);
}

# check for correct arguments present, print usage if errors
unless ($NOERROR && scalar(@ARGV) == 1) {
    print STDERR "Usage: $0 [options...] arguments\n";
    print STDERR <<"EOF";
       --help                  output manpage and exit
       --debug                 enable debug mode
       --verbose               verbose status reporting
       OBJFILE                 macro11 object .obj file
EOF
    # exit if errors...
    die "Aborted due to command line errors.\n";
}

# setup log file as a file, defaults to STDERR if not supplied
my $LOG = FileHandle->new_from_fd(fileno(STDERR),"w");

#----------------------------------------------------------------------------------------------------

# subroutine prototypes

sub chksum (@);
sub rad2asc (@);
sub crc (%);
sub read_rec ($);

#----------------------------------------------------------------------------------------------------

my @mem = (); # real pdp11 memory data bytes
foreach my $adr (0..65535) { $mem[$adr] = 0; }

my ($minadr,$maxadr,$staadr) = ('','',1);
    
# open the input .bin file, die if error
my $OBJ = FileHandle->new("< ".$ARGV[0]);
die "Can't open input binary file '$ARGV[0]'\n" unless defined $OBJ;

while (my @rec = &read_rec($OBJ)) {
    # first two bytes are the load address
    my $adr = shift(@rec); $adr += shift(@rec)<<8;
    printf STDERR "record at address %06o\n", $adr if $DEBUG;
    if (@rec == 0) { $staadr = $adr; next; }
    # rest of the bytes are data (if present)
    $minadr = $adr if $minadr eq '' || $adr < $minadr;
    while (@rec) { $mem[$adr++] = shift(@rec); }
    $maxadr = $adr if $maxadr eq '' || $adr > $maxadr;
}
$OBJ->close;

# print some info
printf "address = (%06o,%06o)  start = %06o\n", $minadr, $maxadr, $staadr;

if ($VERBOSE) {
    # print the whole program image
    for (my $adr = ($minadr&~0xF); $adr <= ($maxadr|0xF); ) {
	printf "  %06o :", $adr;
	for (my $next = $adr+16; $adr < $next; $adr += 2) {
	    if ($adr < $minadr-1 || $adr > $maxadr+1) {
		printf " ......";
	    } else {
		printf " %06o", ($mem[$adr+1]<<8)|$mem[$adr+0];
	    }
	}
	sub fix ($) { my ($c) = @_; $c < 0x20 || $c > 0x7E ? '.' : chr($c); }
	printf "  \"%s\"\n", join('',map(&fix($mem[$adr-16+$_]),(0..15)));
    }
}

#----------------------------------------------------------------------------------------------------

# all done
$LOG->close;
exit;

#----------------------------------------------------------------------------------------------------

# compute checksum (twos complement of the sum of bytes)

sub chksum (@) {

    my $sum = 0;

    map($sum += $_, @_);

    return (-$sum) & 0xFF;
}

#----------------------------------------------------------------------------------------------------

# RAD50 to ASCII decode

sub rad2asc (@) {

    my @str = split(//, ' ABCDEFGHIJKLMNOPQRSTUVWXYZ$.%0123456789'); # RAD50 character subset

    my $ascii = "";
    foreach my $rad50 (@_) {
	$ascii .= $str[int($rad50/1600)%40] . $str[int($rad50/40)%40] . $str[$rad50%40];
    }

    return $ascii;
}

#----------------------------------------------------------------------------------------------------

# crc computation routine

sub crc (%) {

    # pass all args by name
    my %args = @_;

    # all the crcs we know how to compute
    my %crcdat = ( 'CRC-16' => [ 0xA001,     2, 0x0000,     0x0000     ],
		   'CRC-32' => [ 0xEDB88320, 4, 0xFFFFFFFF, 0xFFFFFFFF ] );

    # run next byte thru crc computation, return updated crc
    return $args{-table}[($args{-crc}^$args{-byte}) & 0xFF]^($args{-crc}>>8) if exists($args{-byte});

    # return initial crc value
    return $crcdat{$args{-name}}->[2] if exists($args{-init});

    # return final crc value xored with xorout
    return $args{-crc} ^ $crcdat{$args{-name}}->[3] if exists($args{-last});

    # compute the crc lookup table, return a pointer to it
    if (exists($args{-new})) {
	my $crctab = [];
	my $poly = $crcdat{$args{-name}}->[0];
	foreach my $byte (0..255) {
	    my $data = $byte;
	    foreach (1..8) { $data = ($data>>1) ^ ($data&1 ? $poly : 0); }
	    $$crctab[$byte] = $data;
	}
	return $crctab;
    }
}

#----------------------------------------------------------------------------------------------------

# read a record from the binary file

sub read_rec ($) {

    my ($fh) = @_;

    my ($buf, $cnt, $len, $err) = (0,0,0,0);
    my @pre = ();
    my @dat = ();
    my @suf = ();

    # Binary file format consists of blocks, optionally preceded, separated, and
    # followed by zeroes.  Each block consists of:
    #
    #   001		---
    #   000		 |
    #   lo(length)	 |
    #   hi(length)	 |
    #   lo(address)	 > 'length' bytes
    #   hi(address)	 |
    #   databyte1	 |
    #   :		 |
    #   databyteN	---
    #   checksum
    #

    # skip over strings of 0x00; exit OK if hit EOF
    do { return () unless $cnt = read($fh, $buf, 1); } while (ord($buf) == 0);

    # valid record starts with (1)
    $err = 1 unless $cnt == 1 && ord($buf) == 1;
    push(@pre, ord($buf));

    # second byte must be (0)
    $cnt = read($fh, $buf, 1);
    $err = 2 unless $cnt == 1 && ord($buf) == 0;
    push(@pre, ord($buf));

    # third byte is low byte of record length
    $cnt = read($fh, $buf, 1);
    $err = 3 unless $cnt == 1;
    $len = ord($buf);
    push(@pre, ord($buf));

    # fourth byte is high byte of record length
    $cnt = read($fh, $buf, 1);
    $err = 4 unless $cnt == 1;
    $len += ord($buf)<<8;
    push(@pre, ord($buf));

    # bytes five thru end-1 are two address bytes plus data bytes
    $cnt = read($fh, $buf, $len-4);
    $err = 5 unless $cnt == $len-4 && $len >= 4;
    @dat = unpack("C*", $buf);

    # last byte is checksum
    $cnt = read($fh, $buf, 1);
    $err = 6 unless $cnt == 1;
    my $rcv = ord($buf);
    push(@suf, ord($buf));

    # output the record if debugging
    if ($DEBUG) {
	my $fmt = "%03o";
	my $n = 16;
	my $pre = sprintf("RECORD: [%s] ",join(" ",map(sprintf($fmt,$_),@pre)));
	printf $LOG "\n\n%s", $pre;
	my $k = length($pre);
	my @tmp = @dat;
	while (@tmp > $n) {
	    printf $LOG "%s\n%*s", join(" ",map(sprintf($fmt,$_),splice(@tmp,0,$n))), $k, '';
	}
	printf $LOG "%s", join(" ",map(sprintf($fmt,$_),@tmp)) if @tmp;
	printf $LOG " [%s]\n\n", join(" ",map(sprintf($fmt,$_),@suf));
    }

    # check we have a well formatted record
    die sprintf("Error: invalid binary file record format (%d)", $err) if $err;

    # compare rcv'ed checksum vs exp'ed checksum
    my $exp = &chksum(0x01, $len>>0, $len>>8, @dat);
    die sprintf("Error: Bad checksum exp=0x%02X rcv=0x%02X", $exp, $rcv) unless $exp == $rcv;

    # all is well, return the record
    return @dat;
}

#----------------------------------------------------------------------------------------------------

# the end
