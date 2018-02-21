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

config11.pl - Configure PDP-11 I/O Space Addresses

=head1 SYNOPSIS

config11.pl
S<[--help]>
S<[--debug]>
S<[--verbose]>
<INPFILE
>OUTFILE

=head1 DESCRIPTION

Configures the CSR and vector addresses for a set of
PDP-11 peripherals using the 'standard' autoconfigure
algorithm used by DEC software for device discovery.

=head1 OPTIONS

The following options are available:

=over

=item B<--help>

Output this manpage and exit the program.

=item B<--debug>

Enable debug mode; print input file records as parsed.

=item B<--verbose>

Verbose status; output status messages during processing.

=back

=head1 ERRORS

The following diagnostic error messages can be produced on STDERR.
The meaning should be fairly self explanatory.

C<Aborted due to command line errors> -- bad option or missing file(s)

=head1 EXAMPLES

Some examples of common usage:

  config11.pl --help

  config11.pl --verbose < input.txt > output.txt

=head1 AUTHOR

Don North - donorth <ak6dn _at_ mindspring _dot_ com>

=head1 HISTORY

Modification history:

  2005-09-21 v1.0 donorth - Initial version.

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

# process command line arguments
my $NOERROR = GetOptions( "help"        => \$HELP,
			  "debug"       => \$DEBUG,
			  "verbose"     => \$VERBOSE,
			  );

# init
$VERBOSE = 1 if $DEBUG; # debug implies verbose messages

# say hello
printf STDERR "config11.pl %s by Don North (perl %g)\n", $VERSION, $] if $VERBOSE;

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
unless ($NOERROR && scalar(@ARGV) == 0) {
    print STDERR "Usage: $0 [options...] arguments\n";
    print STDERR <<"EOF";
       --help                       output manpage and exit
       --debug                      enable debug mode
       --verbose                    verbose status reporting
     < INPFILE                      input device list
     > OUTFILE                      output device assignment list
EOF
    # exit if errors...
    die "Aborted due to command line errors.\n";
}

#----------------------------------------------------------------------------------------------------

my %vec = ( # name => [ rank, numvec [,basevec] ]
	    DC11	=> [  1, 2 ],
	    TU58	=> [  1, 2 ],
	    KL11	=> [  2, 2 ], # (1)
	    DL11A	=> [  2, 2 ], # (1)
	    DL11B	=> [  2, 2 ], # (1)
	    DLV11J	=> [  2, 8 ], # (1)
	    DLV11	=> [  2, 2 ], # (1)
	    DLV11F	=> [  2, 2 ], # (1)
	    DP11	=> [  3, 2 ],
	    DM11A	=> [  4, 2 ],
	    DN11	=> [  5, 1 ],
	    DM11BA	=> [  6, 1 ],
	    DM11BB	=> [  6, 1 ],
	    DH11_modem	=> [  7, 1 ],
	    DR11A	=> [  8, 2 ],
	    DRV11B	=> [  8, 2 ],
	    DR11C	=> [  9, 2 ],
	    DRV11	=> [  9, 2 ],
	    PA611	=> [ 10, 4 ],
	    LPD11	=> [ 11, 2 ],
	    DT07	=> [ 12, 2 ],
	    DX11	=> [ 13, 2 ],
	    DL11C	=> [ 14, 2 ],
	    DL11D	=> [ 14, 2 ],
	    DL11E	=> [ 14, 2 ],
	    DL11F	=> [ 14, 2 ],
	    DLV11C	=> [ 14, 2 ],
	    DLV11D	=> [ 14, 2 ],
	    DLV11E	=> [ 14, 2 ],
	    DLV11F	=> [ 14, 2 ],
	    DJ11	=> [ 15, 2 ],
	    DH11	=> [ 16, 2 ],
	    VT40	=> [ 17, 4 ],
	    VSV11	=> [ 17, 4 ],
	    LPS11	=> [ 18, 6 ],
	    DQ11	=> [ 19, 2 ],
	    KW11W	=> [ 20, 2 ],
	    KWV11	=> [ 20, 2 ],
	    DU11	=> [ 21, 2 ],
	    DUV11	=> [ 21, 2 ],
	    DUP11	=> [ 22, 2 ],
	    DV11_modem	=> [ 23, 3 ],
	    LK11A	=> [ 24, 2 ],
	    DWUN	=> [ 25, 2 ],
	    DMC11	=> [ 26, 2 ],
	    DMR11	=> [ 26, 2 ],
	    DZ11	=> [ 27, 2 ],
	    DZS11	=> [ 27, 2 ],
	    DZV11	=> [ 27, 2 ],
	    DZ32	=> [ 27, 2 ],
	    KMC11	=> [ 28, 2 ],
	    LPP11	=> [ 29, 2 ],
	    VMV21	=> [ 30, 2 ],
	    VMV31	=> [ 31, 2 ],
	    VTV01	=> [ 32, 2 ],
	    DWR70	=> [ 33, 2 ],
	    RL11	=> [ 34, 1 ], # (2)
	    RLV11	=> [ 34, 1 ], # (2)
	    TS11	=> [ 35, 1 ], # (2)
	    TU80	=> [ 35, 1 ], # (2)
	    LPA11K	=> [ 36, 2 ],
	    IP11	=> [ 37, 1 ], # (2)
	    IP300	=> [ 37, 1 ], # (2)
	    KW11C	=> [ 38, 2 ],
	    RX11	=> [ 39, 1 ], # (2)
	    RX211	=> [ 39, 1 ], # (2)
	    RXV11	=> [ 39, 1 ], # (2)
	    RXV21	=> [ 39, 1 ], # (2)
	    DR11W	=> [ 40, 1 ],
	    DR11B	=> [ 41, 1 ], # (2)
	    DMP11	=> [ 42, 2 ],
	    DPV11	=> [ 43, 2 ],
	    ML11	=> [ 44, 1 ], # (3)
	    ISB11	=> [ 45, 2 ],
	    DMV11	=> [ 46, 2 ],
	    DEUNA	=> [ 47, 1, 0120 ], # (2)
	    UDA50	=> [ 48, 1, 0154 ], # (2)
	    DMF32	=> [ 49, 8 ],
	    KMS11	=> [ 50, 3 ],
	    PCL11B	=> [ 51, 2 ],
	    VS100	=> [ 52, 1 ],
	    TU81	=> [ 53, 1 ], # (2)
	    KMV11	=> [ 54, 2 ],
	    Reserved	=> [ 55, 2 ],
	    IEX		=> [ 56, 2 ],
	    DHV11	=> [ 57, 2 ],
	    DMZ32	=> [ 58, 6 ],
	    CP132	=> [ 59, 6 ],
	    # (1) A KL11 or DL11 used as a console, has a fixed vector.
	    # (2) The first device of this type has a fixed vector. Any extra devices have a floating vector.
	    # (3) ML11 is a Massbus device which can connect to a UNIBUS via a bus adapter.
	    );

my %csr = ( # name => [ rank, numcsr [,basecsr] ]
	    DJ11   => [  1, 4 ], 
	    DH11   => [  2, 8 ],
	    DQ11   => [  3, 4 ],
	    DU11   => [  4, 4 ],
	    DUV11  => [  4, 4 ],
	    DUP11  => [  5, 4 ],
	    LK11A  => [  6, 4 ],
	    DMC11  => [  7, 4 ],
	    DMR11  => [  7, 4 ],
	    DZ11   => [  8, 4 ],
	    DZV11  => [  8, 4 ],
	    DZS11  => [  8, 4 ],
	    DZ32   => [  8, 4 ],
	    KMC11  => [  9, 4 ],
	    LPP11  => [ 10, 4 ],
	    VMV21  => [ 11, 4 ],
	    VMV31  => [ 12, 8 ],
	    DWR70  => [ 13, 4 ],
	    RL11   => [ 14, 4, 0774400 ],
	    RLV11  => [ 14, 4, 0774400 ],
	    LPA11K => [ 15, 8, 0770460 ],
	    KW11C  => [ 16, 4 ],
	    rsvd   => [ 17, 4 ],
	    RX11   => [ 18, 4, 0777170 ],
	    RX211  => [ 18, 4, 0777170 ],
	    RXV11  => [ 18, 4, 0777170 ],
	    RXV21  => [ 18, 4, 0777170 ],
	    DR11W  => [ 19, 4 ],
	    DR11B  => [ 20, 4, 0772410 ],
	    DMP11  => [ 21, 4 ],
	    DPV11  => [ 22, 4 ],
	    ISB11  => [ 23, 4 ],
	    DMV11  => [ 24, 8 ],
	    DEUNA  => [ 25, 4, 0774440 ],
	    UDA50  => [ 26, 2, 0772150 ],
	    DMF32  => [ 27, 16 ],
	    KMS11  => [ 28, 6 ],
	    VS100  => [ 29, 8 ],
	    TK50   => [ 30, 2, 0774500 ],
	    TU81   => [ 30, 2, 0774500 ],
	    KMV11  => [ 31, 8 ],
	    DHV11  => [ 32, 8 ],
	    DMZ32  => [ 33, 16 ],
	    CP132  => [ 34, 16 ],
	    );

#    printf ("\nRank\tName\tCtrl#\t CSR\n\n");
#    csr = 0760010;
#    for (i = 0; i < RANK_LNT; i++) {
#	if (numctl[i] == 0) {
#	    printf (" %02d\t%s\tgap\t%06o\n", i+1, namtab[i], csr);  }
#	else {
#	    if (fixtab[i])
#		printf (" %02d\t%s\t  1\t%06o*\n", i+1, namtab[i], fixtab[i]);
#	    else {
#		printf (" %02d\t%s\t  1\t%06o\n", i+1, namtab[i], csr);
#		csr = (csr + modtab[i] + 1) & ~modtab[i];  }
#	    for (j = 1; j < numctl[i]; j++) {
#		printf ("\t\t  %d\t%06o\n", j + 1, csr);
#		csr = (csr + modtab[i] + 1) & ~modtab[i];  }
#	    printf (" %\t\tgap\t%06o\n", csr);
#	    }
#	if ((i + 1) < RANK_LNT) csr = (csr + modtab[i+1] + 1) & ~modtab[i+1];
#	}
#    printf ("\n\n");
#    }

#----------------------------------------------------------------------------------------------------

exit;

# the end
