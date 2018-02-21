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

enet2hex.pl - Build .hex image of a DEC ethernet MAC prom

=head1 SYNOPSIS

enet2hex.pl
S<[--help]>
S<[--debug]>
S<[--verbose]>
S<[--macaddr=NN-NN-NN-NN-NN-NN]>
S<[--bytes=N]>
>HEXFILE

=head1 DESCRIPTION

Builds the image of a 'standard' DEC Ethernet MAC address
(station address) 32x8 PROM (82S123 equiv).

=head1 OPTIONS

The following options are available:

=over

=item B<--help>

Output this manpage and exit the program.

=item B<--debug>

Enable debug mode; print input file records as parsed.

=item B<--verbose>

Verbose status; output status messages during processing.

=item B<--macaddr=NN-NN-NN-NN-NN-NN>

The MAC address (in hex format) to be used.

=item B<--bytes=N>

For hex format output files, output N bytes per line (default 16).

=back

=head1 ERRORS

The following diagnostic error messages can be produced on STDERR.
The meaning should be fairly self explanatory.

C<Aborted due to command line errors> -- bad option or missing file(s)

=head1 EXAMPLES

Some examples of common usage:

  enet2hex.pl --help

  enet2hex.pl --verbose --macaddr=01-23-45-67-89-AB > mac.hex

=head1 AUTHOR

Don North - donorth <ak6dn _at_ mindspring _dot_ com>

=head1 HISTORY

Modification history:

  2005-08-05 v1.0 donorth - Initial version.

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
my $romsize = 32; # number of rom addresses
my $bytesper = -1; # bytes per block in output file
my $macaddr = ''; # mac address

# process command line arguments
my $NOERROR = GetOptions( "help"        => \$HELP,
			  "debug"       => \$DEBUG,
			  "verbose"     => \$VERBOSE,
			  "bytes=i"     => \$bytesper,
			  "macaddr=s"	=> \$macaddr,
			  );

# init
$VERBOSE = 1 if $DEBUG; # debug implies verbose messages

# say hello
printf STDERR "enet2hex.pl %s by Don North (perl %g)\n", $VERSION, $] if $VERBOSE;

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
unless ($NOERROR && scalar(@ARGV) == 0 && $macaddr ne '') {
    print STDERR "Usage: $0 [options...] arguments\n";
    print STDERR <<"EOF";
       --help                       output manpage and exit
       --debug                      enable debug mode
       --verbose                    verbose status reporting
       --bytes=N                    bytes per block on output
       --macaddr=NN-NN-NN-NN-NN-NN  mac address
     > OUTFILE                      output .hex/.txt/.bin file
EOF
    # exit if errors...
    die "Aborted due to command line errors.\n";
}

#----------------------------------------------------------------------------------------------------

# compute checksum (twos complement of the sum of bytes)

sub chksum (@) { my $sum = 0; map($sum += $_, @_); (-$sum) & 0xFF; }

#----------------------------------------------------------------------------------------------------

# split the mac address info six hex fields
my @macaddr = map(hex($_)&0xFF, split(/-/, $macaddr));

# check supplied MAC address for validity
die "Invalid MAC address '$macaddr' format"
    unless @macaddr == 6 && $macaddr eq join('-',map(sprintf("%02X",$_),@macaddr));

# echo what was input and we parsed
printf STDERR "MAC ADDR = %02X-%02X-%02X-%02X-%02X-%02X\n", @macaddr if $VERBOSE;

# compute checksum of the MAC address using 16b shift/add w/endaround carry
my $macchk = 0;                                          # init value
for (my $idx = 0; $idx < $#macaddr; $idx += 2) {         # loop on words
    $macchk *= 2;                                        # shift left 1
    $macchk  = ($macchk + ($macchk>>16))&0xFFFF;         # end around carry
    $macchk += ($macaddr[$idx+0]<<8) + $macaddr[$idx+1]; # add two bytes
    $macchk  = ($macchk + ($macchk>>16))&0xFFFF;         # end around carry
}
printf STDERR "MAC checksum is %06o (0x%04X)\n", ($macchk) x 2 if $VERBOSE;

# split checksum into high/low bytes
my @macchk = (($macchk>>8)&0xFF, ($macchk>>0)&0xFF);

# build the entire device
my @buf = (@macaddr, @macchk, reverse(@macchk), reverse(@macaddr),
	   @macaddr, @macchk, (0xFF,0x00,0x55,0xAA)x2);

# print checksum of entire device
my $chksum = 0; map($chksum += $_, @buf);
printf STDERR "ROM checksum is %06o (0x%04X)\n", $chksum, $chksum if $VERBOSE;

#----------------------------------------------------------------------------------------------------

# output the entire PROM buffer as an intel hex file

$bytesper = 16 if $bytesper <= 0;

for (my $idx = 0; $idx < $romsize; $idx += $bytesper) {
    my $cnt = $idx+$bytesper <= $romsize ? $bytesper : $romsize-$idx; # N bytes or whatever is left
    my @dat = @buf[$idx..($idx+$cnt-1)]; # get the data
    my $dat = join('', map(sprintf("%02X",$_),@dat)); # map to ascii text
    printf ":%02X%04X%02X%s%02X\n", $cnt, $idx, 0x00, $dat, &chksum($cnt, $idx>>0, $idx>>8, 0x00, @dat);
}

printf ":%02X%04X%02X%s%02X\n", 0x00, 0x0000, 0x01, '', &chksum(0x0, 0x0000>>0, 0x0000>>8, 0x01);

#----------------------------------------------------------------------------------------------------

exit;

# the end
