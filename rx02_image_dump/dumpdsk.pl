#!/usr/bin/perl -w

# Copyright (c) 2007 Don North
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

# external local modules search path
BEGIN { unshift(@INC, $FindBin::Bin);
        unshift(@INC, $ENV{PERL5LIB}) if defined($ENV{PERL5LIB}); # cygwin bugfix
        unshift(@INC, '.'); }

# external local modules

# generic defaults
my $VERSION = 'v0.1'; # version of code
my $ONWIN = $^O eq 'MSWin32'; # true if running under WinPerl
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
printf STDERR "dumpdsk.pl %s by Don North (perl %g)\n", $VERSION, $] if $VERBOSE;

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
       DSKFILE                 binary .dsk file image
EOF
    # exit if errors...
    die "Aborted due to command line errors.\n";
}

#-------------------------------------------------------------------------------------

# read blocks from the disk image file

foreach my $file (@ARGV) {

    if (open(DSK, "< $file")) {

	my $SECperTRK = 26;
	my $buf = undef;
	my $cnt = -1;
	my $blk = 0;
	my $len = 128;

	# read until EOF
	while (!eof(DSK)) {
	    # read one block
	    $cnt = read(DSK, $buf, $len);
	    printf "ERROR: CNT<>LEN %d<>%d\n", $cnt, $len unless $cnt == $len;
	    # print it out
	    my $sec = ($blk % $SECperTRK)+1;
	    my $trk = int($blk / $SECperTRK);
	    printf "blk=%-4d trk=%-2d sec=%d\n", $blk,$trk,$sec;
	    my @buf = map {ord($_)} split(//,$buf);
	    my $i = 0;
	    while ($i < $cnt) {
		printf " %02X", $buf[$i];
		printf "\n" if $i % 16 == 15;
		++$i;
	    }
	    printf "\n" unless $i % 16 == 15;
	    $blk++;
	}
	printf "Total of %d blocks read\n", $blk;
	close(DSK);
    } else {
	die "Can't open file '$file'";
    }

}

#-------------------------------------------------------------------------------------

exit;

# the end
