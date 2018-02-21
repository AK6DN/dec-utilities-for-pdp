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

diffrom.pl - Compare two .hex/.bin format PROM files

=head1 SYNOPSIS

diffrom.pl
S<[--help]>
S<[--debug]>
S<[--verbose]>
S<FILE1>
S<FILE2>

=head1 DESCRIPTION

Compares two PROM files, byte by byte. Format is determined
by file extension: .hex for Intel hex format, .bin for binary.
Outputs a list of all bytes that differ (if any).

=head1 OPTIONS

The following options are available:

=over

=item B<--help>

Output this manpage and exit the program.

=item B<--debug>

Enable debug mode; print input file records as parsed.

=item B<--verbose>

Verbose status; outputs a message if files are equal.

=back

=head1 ERRORS

The following diagnostic error messages can be produced on STDERR.
The meaning should be fairly self explanatory.

C<Aborted due to command line errors> -- bad option or missing file(s)

C<Can't open input file '$file'> -- bad filename or unreadable file

C<File '%s': Unknown record type '%s' ignored> -- bad record type in hex file

C<File '%s': Bad data count, exp=0x%02X rcv=0x%02X, line='%s'> - bad record length in hex file

C<File '%s': Bad checksum, exp=0x%02X rcv=0x%02X, line='%s'> - checksum error in hex file

=head1 EXAMPLES

Some examples of common usage:

  diffrom.pl --help

  diffrom.pl --verbose file1.bin file2.hex

=head1 AUTHOR

Don North - donorth <ak6dn _at_ mindspring _dot_ com>

=head1 HISTORY

Modification history:

  2005-05-05 v1.0 donorth - Initial version.

=cut

# options
use strict;
	
# external standard modules
use Getopt::Long;
use Pod::Text;
use FindBin;

# external local modules search path
BEGIN { unshift(@INC, $FindBin::Bin);
        unshift(@INC, $ENV{PERL5LIB}) if defined($ENV{PERL5LIB}); # cygwin bugfix
        unshift(@INC, '.'); }

# external local modules

# generic defaults
my $VERSION = 'v1.0'; # version of code
my $HELP = 0; # set to 1 for man page output
my $DEBUG = 0; # set to 1 for debug messages
my $VERBOSE = 0; # set to 1 for verbose messages

# specific defaults
my $MODE = 'OCT'; # or 'OCT' or 'DEC' or 'BIN'
my $SIZE = 'BYTE'; # or 'WORD'

# process command line arguments
my $NOERROR = GetOptions( "help"        => \$HELP,
			  "debug"       => \$DEBUG,
			  "verbose"     => \$VERBOSE,
			  "bin"         => sub { $MODE = 'BIN'; },
			  "oct"         => sub { $MODE = 'OCT'; },
			  "dec"         => sub { $MODE = 'DEC'; },
			  "hex"         => sub { $MODE = 'HEX'; },
			  "byte"        => sub { $SIZE = 'BYTE'; },
			  "word"        => sub { $SIZE = 'WORD'; },
			  );

# init
$VERBOSE = 1 if $DEBUG; # debug implies verbose messages

# say hello
printf STDERR "diffrom.pl %s by Don North (perl %g)\n", $VERSION, $] if $VERBOSE;

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
unless ($NOERROR && scalar(@ARGV) >= 1) {
    print STDERR "Usage: $0 [options...] arguments\n";
    print STDERR <<"EOF";
       --help                  output manpage and exit
       --debug                 enable debug mode
       --verbose               verbose status reporting
       FILE1                   first ROM file
       FILE2                   second ROM file
EOF
    # exit if errors...
    die "Aborted due to command line errors.\n";
}

#----------------------------------------------------------------------------------------------------

# compute checksum (twos complement of the sum of bytes)
sub chksum (@) { my $sum = 0; map($sum += $_, @_); (-$sum) & 0xFF; }

# compute checksum (sum of bytes)
sub binsum (@) { my $sum = 0; map($sum += $_, @_); $sum; }

# convert string of byte hex characters to an array of numbers
sub hexa ($) {
    my ($dat) = @_;
    my @dat = ();
    while ($dat) { push(@dat,hex(substr($dat,0,2))); $dat = substr($dat,2); }
    return @dat;
}

# read a hex file into an array
sub readhex ($$) {

    my ($file,$buf) = @_;

    my $extadr = 0; # extended address offset
    my $chksum = 0; # total device checksum

    # read the input hex-format stream into a buffer
    open(HEX, "< $file") || die "Can't open input file '$file'\n";
    while (my $line = scalar(<HEX>)) {
	$line =~ s/[\015\012]+$//; # strip EOLs
	if ($line =~ m/^:([0-9A-F]{2})([0-9A-F]{4})([0][0-3])([0-9A-F]{0,})([0-9A-F]{2})$/i) {
	    # 00 data record:              :NNAAAA00DDDDD...DDDDCC
	    # 01 end record:               :NNAAAA01CC
	    # 02 extended address record:  :NNAAAA02EEEECC
	    # 03 start record:             :NNAAAA03SSSSCC
	    my ($typ,$cnt,$adr,$chk,@dat) = (hex($3),hex($1),hex($2),hex($5),hexa($4));

	    # validate data byte count
	    unless (@dat == $cnt) {
		printf STDERR "File '%s': Bad data count, exp=0x%02X rcv=0x%02X, line='%s'\n",
		              $file, $cnt, scalar(@dat), $line;
		next;
	    }

	    # compute checksum, validate
	    my $cmp = &chksum($typ, $cnt, $adr, $adr>>8, @dat);
	    unless ($cmp == $chk) {
		printf STDERR "File '%s': Bad checksum, exp=0x%02X rcv=0x%02X, line='%s'\n",
		              $file, $cmp, $chk, $line;
		next;
	    }

	    # print what we read if debugging
	    printf STDERR "file=%s lin=%s typ=%d cnt=0x%02X adr=0x%04X chk=0x%02X dat=%s\n",
	                  $file, $line, $typ, $cnt, $adr, $chk,
	                  join('',map(sprintf("%02X",$_),@dat)) if $DEBUG;

	    # process each record type
	    if ($typ == 0) {
		# data record
		for (my $idx = 0; $idx < $cnt; $idx++) {
		    $chksum += ($$buf[$extadr+$adr+$idx] = $dat[$idx]); }
	    } elsif ($typ == 2) {
		# save extended address
		$extadr = ($dat[0]<<12)|($dat[1]<<4);
	    } elsif ($typ == 1) {
		# exit if hit last
		last;
	    }

	} else {
	    printf STDERR "File '%s': Unknown record type '%s' ignored\n", $file, $line;
	}

    } # while (my $line)
    close(HEX);

    # print stats if requested
    printf STDERR "File '%s': size=0x%X (%dx8), checksum=0x%X\n",
                  $file, (scalar(@$buf))x2, $chksum if $VERBOSE;

    return;
}

# read a binary file into an array
sub readbin ($$) {

    my ($file,$buf) = @_;

    # read the input hex-format stream into a buffer
    my $dat = undef;
    open(BIN, "< $file") || die "Can't open input file '$file'\n";
    read(BIN, $dat, 1<<20);
    close(BIN);
    @$buf = unpack("C*", $dat);

    # print stats if requested
    printf STDERR "File '%s': size=0x%X (%dx8), checksum=0x%X\n",
                  $file, (scalar(@$buf))x2, &binsum(@$buf) if $VERBOSE;

    return;
}

# read a file into an array
sub readfile ($$) {

    my ($file,$buf) = @_;

    &readhex($file, $buf) if $file =~ m/[.]hex$/i;
    &readbin($file, $buf) if $file =~ m/[.]bin$/i;

    return;
}

#----------------------------------------------------------------------------------------------------

my @buf1 = (); # first ROM file
my @buf2 = (); # second ROM file

# if exactly two files specified do the compare
if (@ARGV == 2) {

    # read the two files
    &readfile(shift(@ARGV), \@buf1); 
    &readfile(shift(@ARGV), \@buf2); 

    # compare the two files
    my $err = 0;
    my $len = @buf1 >= @buf2 ? @buf1 : @buf2;
    for (my $adr = 0; $adr < $len; $adr += $SIZE eq 'BYTE' ? 1 : 2) {
	# get bytes/words
	my $dat1 = $SIZE eq 'BYTE' ? $buf1[$adr] : ($buf1[$adr+1]<<8)|($buf1[$adr+0]<<0);
	my $dat2 = $SIZE eq 'BYTE' ? $buf2[$adr] : ($buf2[$adr+1]<<8)|($buf2[$adr+0]<<0);
	# check if same
	next if $dat1 == $dat2;
	# print if different
	if ($SIZE eq 'BYTE') {
	    if ($MODE eq 'HEX') {
		printf "Addr=0x%04X File1=0x%02X File2=0x%02X\n", $adr, $dat1, $dat2;
	    } elsif ($MODE eq 'DEC') {
		printf "Addr=%-5u File1=%-3u File2=%-3u\n", $adr, $dat1, $dat2;
	    } elsif ($MODE eq 'OCT') {
		printf "Addr=%06o File1=%03o File2=%03o\n", $adr, $dat1, $dat2;
	    } elsif ($MODE eq 'BIN') {
		printf "Addr=0b%016b File1=0b%08b File2=0b%08b\n", $adr, $dat1, $dat2;
	    }
	} elsif ($SIZE eq 'WORD') {
	    if ($MODE eq 'HEX') {
		printf "Addr=0x%04X File1=0x%04X File2=0x%04X\n", $adr, $dat1, $dat2;
	    } elsif ($MODE eq 'DEC') {
		printf "Addr=%-5u File1=%-5u File2=%-5u\n", $adr, $dat1, $dat2;
	    } elsif ($MODE eq 'OCT') {
		printf "Addr=%06o File1=%06o File2=%06o\n", $adr, $dat1, $dat2;
	    } elsif ($MODE eq 'BIN') {
		printf "Addr=0b%016b File1=0b%016b File2=0b%016b\n", $adr, $dat1, $dat2;
	    }
	}
	$err++;
    }
    printf "Files are %s\n", $err ? "different" : "identical" if $err || $VERBOSE;

    exit($err ? 1 : 0);

} else {

    # if just one (or three or more) than just print stats and exit
    while (@ARGV) {
	# read the file
	&readfile(shift(@ARGV), \@buf1); 
    }

    exit(0);

}

#----------------------------------------------------------------------------------------------------

# the end
