#!/usr/bin/perl -w
#!/usr/local/bin/perl -w

# Copyright (c) 2005-2016 Don North
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

hex2mac.pl - Disassembles PDP11 hex/binary files

=head1 SYNOPSIS

hex2mac.pl
S<[--help]>
S<[--debug]>
S<[--verbose]>
S<[--option=STRING]>
S<[--boot]>
S<[--console]>
S<[--binary]>
S<[--logfile=LOGFILE]>
S<--infile=INFILE>
S<--outfile=OUTFILE>

=head1 DESCRIPTION

Disassembles an M9312 Intel-hex format PROM image
file (either a boot PROM or a console/diagnostic PROM)
to macro-11 source format.

=head1 OPTIONS

The following options are available:

=over

=item B<--help>

Output this manpage and exit the program.

=item B<--debug>

Enable debug mode; print input file records as parsed.

=item B<--verbose>

Verbose mode (does nothing right now).

=item B<--boot>

Input file is an M9312 boot PROM image (512x4, half-used).

=item B<--console>

Input file is an M9312 diagnostic/console PROM image (1024x4).

=item B<--binary>

Input file is a PDP-11 binary program file (BIN/BIC/LDA/SYS).

=item B<--option=STRING>

For console PROMs, provide option flag to control disassembly.

=item B<--logfile=FILENAME>

Generate debug output into this file.

=item B<--infile=FILENAME>

Input file in selected format (HEX, BIN, OBJ, etc).

=item B<--outfile=FILENAME>

Output text file in .mac format.

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

  hex2mac.pl --help

  hex2mac.pl --boot <23-751A9.hex >23-751A9.mac

=head1 NOTES

The disassembly process knows the 'standard' entry points
for boot and console PROMS, but is not real smart about multiple
entry points (it could be improved, but was not really worth
the extra trouble, as there are so few of these PROM images).

Console format was tuned for disassembling the 248F1 11/34,etc PROM.
Disassembly of the 616F1 11/70 PROM (not tried) will likely require
massive tuning to the internal entry point hash table.

=head1 AUTHOR

Don North - donorth <ak6dn _at_ mindspring _dot_ com>

=head1 HISTORY

Modification history:

  2005-05-05 v1.0 donorth - Initial version.
  2005-10-29 v1.1 donorth - Added auto-detect of boot continue PROM.
  2016-09-09 v1.2 donorth - Added binary mode.

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
my $VERSION = 'v1.2'; # version of code
my $HELP = 0; # set to 1 for man page output
my $DEBUG = 0; # set to 1 for debug messages
my $VERBOSE = 0; # set to 1 for verbose messages

# specific defaults
my $crctype = 'CRC-16'; # type of crc calc to do
my $memsize; # number of instruction bytes allowed
my $memfill; # memory fill pattern
my %excaddr; # words to be skipped in rom crc calc
my $rombase; # base address of rom image
my $romsize; # number of rom addresses
my $romfill; # rom fill pattern
my $romtype = 'NONE'; # default rom type
my $option = ''; # option string
my $infile = undef; # input filename
my $outfile = undef; # output filename
my $logfile = undef; # log filename

# process command line arguments
my $NOERROR = GetOptions( "help"        => \$HELP,
			  "debug"       => \$DEBUG,
			  "verbose"     => \$VERBOSE,
			  "boot"        => sub { $romtype = 'BOOT'; },
			  "console"     => sub { $romtype = 'DIAG'; },
			  "binary"      => sub { $romtype = 'BINA'; },
			  "option=s"    => \$option,
			  "infile=s"    => \$infile,
			  "outfile=s"   => \$outfile,
			  "logfile=s"   => \$logfile,
			  );

# init
$VERBOSE = 1 if $DEBUG; # debug implies verbose messages

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
unless ($NOERROR
	&& scalar(@ARGV) == 0
	&& defined($infile)
	&& defined($outfile)
	&& $romtype ne 'NONE'
    ) {
    printf STDERR "hex2mac.pl %s by Don North (perl %g)\n", $VERSION, $];
    print STDERR "Usage: $0 [options...] arguments\n";
    print STDERR <<"EOF";
       --help                  output manpage and exit
       --debug                 enable debug mode
       --verbose               verbose status reporting
       --boot                  M9312 boot prom
       --console               M9312 console/diagnostic prom
       --binary                binary program load image
       --option=STRING         option string for console prom
       --infile=INFILE         input object/hex pdp11 code file
       --outfile=OUTFILE       output ..mac pdp11 macro11 file
       --logfile=LOGFILE       logging message file
EOF
    # exit if errors...
    die "Aborted due to command line errors.\n";
}

# setup log file as a file, defaults to STDERR if not supplied
my $LOG = defined($logfile) ? FileHandle->new("> ".$logfile) : FileHandle->new_from_fd(fileno(STDERR),"w");

#----------------------------------------------------------------------------------------------------

# subroutine prototypes

sub pdp11 ($);
sub hexa ($);
sub trim ($);
sub chksum (@);
sub rad2asc (@);
sub crc (%);
sub read_rec ($);

#----------------------------------------------------------------------------------------------------

# fill in the parameters of the device

if ($romtype eq 'BOOT') {

    # M9312 512x4 boot prom
    %excaddr = ( 024=>1 ); # words to be skipped in rom crc calc
    $memsize = 128; # number of instruction bytes allowed
    $memfill = 0x00; # memory fill pattern
    $romsize = 512; # number of rom addresses (must be a power of two)
    $romfill = 0x00; # rom fill pattern
    $rombase = 0173000; # base address of rom

} elsif ($romtype eq 'DIAG') {

    # M9312 1024x4 diagnostic/console prom
    %excaddr = ( ); # words to be skipped in rom crc calc
    $memsize = 512; # number of instruction bytes allowed
    $memfill = 0x00; # memory fill pattern
    $romsize = 1024; # number of rom addresses
    $romfill = 0x00; # rom fill pattern
    $rombase = 0165000; # base address of rom

} elsif ($romtype eq 'BINA') {

    # program load image ... 56KB address space maximum
    %excaddr = ( ); # bytes to be skipped in rom crc calc
    $memsize = 0; # number of instruction bytes allowed
    $memfill = 0x00; # memory fill pattern
    $romsize = 8*8192; # number of rom addresses (must be a power of two)
    $romfill = 0x00; # image fill pattern
    $rombase = 0; # base address of binary image

} else {

    # unknown ROM type code
    die "ROM type '$romtype' is not supported!\n";

}

if ($VERBOSE) {
    printf $LOG "ROM type is '%s'\n", $romtype;
    printf $LOG "ROM space is %d. bytes\n", $memsize;
    printf $LOG "ROM length is %d. addresses\n", $romsize;
    printf $LOG "ROM base address is 0%06o\n", $rombase;
}

#----------------------------------------------------------------------------------------------------

# read/process the input object/binary file records

# physical PROM data bytes
my @rom = ((0) x $romsize);

# real pdp11 memory data words
my @wrd = ();

# open the input file, die if error
my $INP = FileHandle->new("< ".$infile);
die "Error: can't open input file '$infile'\n" unless defined $INP;

if ($romtype eq 'BOOT' or $romtype eq 'DIAG') {

    # process hex rom format

    # extended address offset
    my $extadr = 0;

    # read the input hex-format stream into a buffer
    while (my $line = scalar(<$INP>)) {
	$line =~ s/[\015\012]+$//; # strip EOLs
	if ($line =~ m/^:([0-9A-F]{2})([0-9A-F]{4})([0][0-3])([0-9A-F]{0,})([0-9A-F]{2})$/i) {
	    # 00 data record:              :NNAAAA00DDDDD...DDDDCC
	    # 01 end record:               :NNAAAA01CC
	    # 02 extended address record:  :NNAAAA02EEEECC
	    # 03 start record:             :NNAAAA03SSSSCC
	    my ($typ,$cnt,$adr,$chk,@dat) = (hex($3),hex($1),hex($2),hex($5),hexa($4));

	    # validate data byte count
	    unless (@dat == $cnt) {
		printf $LOG "Bad data count, exp=0x%02X rcv=0x%02X, line='%s'\n",
		            $cnt, scalar(@dat), $line;
		next;
	    }

	    # compute checksum, validate
	    my $cmp = chksum($typ, $cnt, $adr, $adr>>8, @dat);
	    unless ($cmp == $chk) {
		printf $LOG "Bad checksum, exp=0x%02X rcv=0x%02X, line='%s'\n", $cmp, $chk, $line;
		next;
	    }

	    # print what we read if debugging
	    printf $LOG "lin=%s typ=%d cnt=0x%02X adr=0x%04X chk=0x%02X dat=%s\n",
	                $line, $typ, $cnt, $adr, $chk,
	                join('',map(sprintf("%02X",$_),@dat)) if $DEBUG;

	    # process each record type
	    if ($typ == 0) {
		# data record
		for (my $idx = 0; $idx < $cnt; $idx++) { $rom[$extadr+$adr+$idx] = $dat[$idx]; }
	    } elsif ($typ == 2) {
		# save extended address
		$extadr = $adr<<4;
	    } elsif ($typ == 1) {
		# exit if hit last
		last;
	    }

	} else {
	    printf $LOG "Unknown record type '%s' ignored\n", $line;
	}
    }

    # now we have a buffer full of data, process it
    for (my $idx = 0; $idx < $romsize; $idx += 4) {
	# true byte address
	my $adr = $idx>>1;
	# merge 4 nibbles into 16 data bits
	my $dat = ($rom[$idx+3]<<12) | ($rom[$idx+2]<<8) | ($rom[$idx+1]<<4) | ($rom[$idx+0]<<0);
	$dat = $dat ^ 0x1C00; # bits 12:10 get inverted
	$dat = ($dat & 0xFEFE) | ((0x0100&$dat)>>8) | ((0x0001&$dat)<<8); # swap bits 8,0
	printf $LOG "adr=%06o dat=%06o\n", $adr, $dat if $DEBUG;
	# store it
	$wrd[$adr] = $dat;
    }

} elsif ($romtype eq 'BINA') {

    # process binary format file

    while (my @rec = &read_rec($INP)) {

	my $len = scalar(@rec)-2;
	my $minadr = $rec[1]*256+$rec[0];

	foreach my $i (0..($len-1)) {
	    my ($adr,$dat) = ($minadr+$i,$rec[2+$i]);
	    printf $LOG "adr=%06o dat=%03o\n", $adr, $dat if $DEBUG;
	    $wrd[$adr] = $memfill unless defined $wrd[$adr];
	    if ($adr & 1) {
		# upper/odd byte
		$wrd[$adr-1] = ($wrd[$adr-1]&0x00FF) | ($dat<<8);
	    } else {
		# lower/even byte
		$wrd[$adr+0] = ($wrd[$adr+0]&0xFF00) | ($dat<<0);
	    }
	    $memsize = $adr if $adr > $memsize;
	}
	
    }

    if ($DEBUG) {
	for (my $i = 0; defined $wrd[$i]; $i += 2) {
	    my $ub = ($wrd[$i]>>8)&0xFF; $ub = 056 if $ub < 040 || $ub > 0176;
	    my $lb = ($wrd[$i]>>0)&0xFF; $lb = 056 if $lb < 040 || $lb > 0176;
	    printf $LOG "wrd[%06d]=%06o \"%c%c\"\n", $i, $wrd[$i], $lb, $ub;
	}
    }

}

# done with input file
$INP->close;

#----------------------------------------------------------------------------------------------------

# disassemble the prom image we just unmangled

my $OUT = FileHandle->new("> ".$outfile);
die "Error: can't open output file '$outfile'\n" unless defined $OUT;

my %entry = ();
my %label = ();
my $label = 0;
my $continuation = ($wrd[0] == 0177776); # a continuation boot PROM

if ($romtype eq 'DIAG') {
    %label = ( 020=>'DIAG', 0144=>'NODIAG', 0564=>'RSTRT' );
} elsif ($romtype eq 'BOOT') {
    if ($continuation) {
	%label = ( 02=>'CONT' );
    } else {
	%label = ( 04=>'PUP0ND', 06=>'PUP0D', 012=>'BOOTSZ', 016=>'BOOTNZ', 020=>'SECD' );
    }
} elsif ($romtype eq 'BINA') {
    %label = ( 0174=>'START',
	       0123=>'WTERR', 0134=>'RDERR', 0150=>'ILLCMD' );
}

foreach my $pass (1..2) {

    if ($romtype eq 'DIAG') {
	# these entry points found by inspection/iteration for the 248F1 PROM
	# probably will be different for 616F1 PROM (hasn't been tried yet)
	if ($option eq '248F1') {
	    %entry = ( 0020=>1, 0144=>1, 0564=>1,
		       0112=>1, 0120=>1, 0124=>1,
		       0150=>1, 0154=>1, 0160=>1, 0166=>1, 0172=>1, 0200=>1, 0210=>1,
		       0214=>1, 0220=>1, 0320=>1, 0342=>1, 0352=>1, 0376=>1, 0446=>1,
		       0510=>1, 0650=>1, 0662=>1, 0700=>1,
		       );
	} elsif ($option eq '616F1') {
	    %entry = ( 0020=>1, 0144=>1, 0564=>1,
		       0000=>1, 0340=>1, 0342=>1, 0352=>1, 0354=>1, 0360=>1, 0362=>1,
		       0554=>1, 0676=>1, 0714=>1, 0716=>1, 0744=>1, 0772=>1,
		       );
	} elsif ($option eq '446F1') {
	    %entry = ( 0020=>1, 0144=>1, 0564=>1,
		       0000=>1, 0010=>1, 0016=>1, 0070=>1, 0146=>1, 0366=>1, 0370=>1,
		       0400=>1, 0402=>1, 0406=>1, 0410=>1, 0466=>1, 0652=>1, 0662=>1,
		       0666=>1, 0676=>1, 0702=>1, 0704=>1, 0714=>1, 0736=>1,
		       );
	} elsif ($option eq '774F1') {
	    %entry = ( 0020=>1, 0144=>1, 0564=>1,
		       0006=>1, 0316=>1, 0364=>1, 0552=>1,
		       );
	} else {
	    %entry = ( 0020=>1, 0144=>1, 0564=>1 );
	}
    } elsif ($romtype eq 'BOOT') {
	# standard entry points for a single-device boot PROM
	if ($continuation) {
	    %entry = ( 02=>1 );
	} else {
	    %entry = ( 04=>1, 06=>1, 012=>1, 016=>1, 020=>1 );
	}
    } elsif ($romtype eq 'BINA') {
	# binary load image file
	%entry = ( 0174=>1 );
    }

    $label = 1; # reset label counter

    if ($pass == 1) {

	# now iterate over the words of interest
	for (my $adr = 0; $adr < $memsize; $adr += 2) {
	    if (exists($entry{$adr})) { # an instr should start here
		my ($cntr,$inst) = &pdp11($adr);
	    }
	}

    } elsif ($pass == 2) {

	printf $OUT "\t.sbttl\t%s\n\n", "M9312 $romtype prom";
	printf $OUT "\t.asect\n\t.=%o\n\n", $rombase;

	# now iterate over the words of interest
	for (my $adr = 0; $adr < $memsize; $adr += 2) {

	    if (exists($entry{$adr})) { # an instr should start here

		my ($cntr,$inst) = &pdp11($adr);
		printf $OUT "%06o:\t%06o\t", $adr, $wrd[$adr] if $DEBUG;
		printf $OUT "%s:", $label{$adr} if $label{$adr};
		printf $OUT "\t%s\n", $inst;
		while (--$cntr > 0) {
		    $adr += 2;
		    printf $OUT "%06o:\t%06o\n", $adr, $wrd[$adr] if $DEBUG;
		}

	    } elsif ($romtype eq 'BOOT' && $adr == 0 && !$continuation) { # special string for boot

		printf $OUT "%06o:\t%06o\t", $adr, $wrd[$adr] if $DEBUG;
		printf $OUT "\t.ascii\t\"%c%c\"\n", ($wrd[$adr]>>0)&0xFF, ($wrd[$adr]>>8)&0xFF;

	    } else { # just print it as a data word

		printf $OUT "%06o:\t%06o\t", $adr, $wrd[$adr] if $DEBUG;
		printf $OUT "%s:", $label{$adr} if $label{$adr};
		my $lb = ($wrd[$adr]>>0)&0xFF; $lb = 056 if $lb < 040 || $lb > 0176;
		my $ub = ($wrd[$adr]>>8)&0xFF; $ub = 056 if $ub < 040 || $ub > 0176;
		printf $OUT "\t.word\t%06o\t\t; \"%c%c\"\n", $wrd[$adr], $lb, $ub;

	    }

	}

	printf $OUT "\n\t.end\n";

    }

}

# all done
$OUT->close;
exit;

#----------------------------------------------------------------------------------------------------

# disassemble a pdp11 instr at $adr in image $wrd[]

sub pdp11 ($) {

    my ($adr) = @_;

    # generate a register specifier
    sub _r {
	my $r = $_[0]&7;
	return $r == 7 ? 'pc' : $r == 6 ? 'sp' : 'r'.$r;
    } # sub _r

    # generate src/dst operand reference
    sub _mode {
	my ($mode, $adr, $off) = @_;
	my ($m, $r) = (($mode>>3)&7, _r(($mode>>0)&7));
	if ($r eq 'pc') {
	    my $ea = ($adr + $off + $wrd[$adr]) & 0xFFFF;
	    if    ($m == 0) { return sprintf("pc"); }
	    elsif ($m == 1) { return sprintf("(pc)"); }
	    elsif ($m == 2) { return sprintf("#%o", $wrd[$adr]); }
	    elsif ($m == 3) { return sprintf("\@#%o", $wrd[$adr]); }
	    elsif ($m == 4) { return sprintf("-(pc)"); }
	    elsif ($m == 5) { return sprintf("\@-(pc)"); }
	    elsif ($m == 6) { return sprintf("%s", exists($label{$ea})?$label{$ea}:sprintf("0%o",$ea)); }
	    elsif ($m == 7) { return sprintf("\@%s", exists($label{$ea})?$label{$ea}:sprintf("0%o",$ea)); }
	} else {
	    if    ($m == 0) { return sprintf("%s", $r); }
	    elsif ($m == 1) { return sprintf("(%s)", $r); }
	    elsif ($m == 2) { return sprintf("(%s)+", $r); }
	    elsif ($m == 3) { return sprintf("\@(%s)+", $r); }
	    elsif ($m == 4) { return sprintf("-(%s)", $r); }
	    elsif ($m == 5) { return sprintf("\@-(%s)", $r); }
	    elsif ($m == 6) { return sprintf("%o(%s)", $wrd[$adr],$r); }
	    elsif ($m == 7) { return sprintf("\@%o(%s)", $wrd[$adr],$r); }
	}
    } # sub _mode

    # return 1/0 if indicated address mode will eat an instr stream word
    sub _eat {
	my ($mode) = @_;
	my ($m, $r) = (($mode>>3)&7, ($mode>>0)&7);
	return ($r == 7 && ($m == 2 || $m == 3)) || $m == 6 || $m == 7 ? 1 : 0;
    } # sub _eat

    my $wrd = $wrd[$adr]; # instruction word
    my $str = 'NONE'; # build the instruction here
    my $cnt = 1; # number of instruction words total
    delete($entry{$adr}); # eat the current instruction

    if ($wrd >= 000000 && $wrd <= 000007) { # ok
	#
	# misc single-word zop instructions
	#
	$str = ('halt','wait','rti','bpt','iot','reset','rtt','mfpt')[$wrd&7];
	$entry{$adr+2}++ unless $str =~ m/^(halt|rti|rtt)$/i;

    } elsif ($wrd >= 0104000 && $wrd <= 0104377) { # ok
	#
	# trap single-word sop instructions
	#
	my $opc = ('emt','trap')[($wrd&000400)>>8];
	$str = sprintf("%s\t%o", $opc, $wrd&0377);
	$entry{$adr+2}++;

    } elsif ($wrd >= 000230 && $wrd <= 000237) { # ok
	#
	# priority-level sop single-word instruction
	#
	$str = sprintf("spl\t%o", $wrd&7);
	$entry{$adr+2}++;

    } elsif ($wrd >= 000240 && $wrd <= 000277) { # ok
	#
	# condition code zop single-word instructions
	#
	if    ($wrd == 000240) { $str = 'nop'; }
	elsif ($wrd == 000260) { $str = 'nop2'; }
	elsif ($wrd == 000257) { $str = 'ccc'; }
	elsif ($wrd == 000277) { $str = 'scc'; }
	else { $str = join('', $wrd&020?'se':'cl', $wrd&010?'n':'',$wrd&04?'z':'',$wrd&02?'v':'',$wrd&01?'c':''); }
	$entry{$adr+2}++;

    } elsif ($wrd >= 000400 && $wrd <= 003777 || $wrd >= 0100000 && $wrd <= 0103777) { # ok
	#
	# conditional branch sop single-word instructions
	#
	my $opc = ('xxx','br', 'bne','beq', 'bge','blt','bgt','ble',
		   'bpl','bmi','bhi','blos','bvc','bvs','bcc','bcs'
		   ) [ (($wrd&0100000)>>12) | (($wrd&03400)>>8) ];
	my $off = $wrd&0377; $off = -(0400-$off) if $off >= 0200;
	my $npc = $adr+2 + 2*$off;
	$label{$npc} = 'L'.$label++ unless exists($label{$npc});
	if (0) {
	    $str = sprintf("%s\t.%s%o\t\t; %06o [%s]",
			   $opc, $off < 0 ? '-' : '+', abs($npc-$adr), $npc, $label{$npc});
	} else {
	    $str = sprintf("%s\t%s\t\t; %06o [.%s%o]",
			   $opc, $label{$npc}, $npc, $off < 0 ? '-' : '+', abs($npc-$adr));
	}
	$entry{$adr+2}++ if $opc ne 'br';
	$entry{$npc}++;

    } elsif ($wrd >= 077000 && $wrd <= 077777) { # maybe
	#
	# subtract-one-branch dop single-word instruction
	#
	my $off = $wrd&077;
	my $npc = $adr+2 - 2*$off;
	$label{$npc} = 'L'.$label++ unless exists($label{$npc});
	if (0) {
	    $str = sprintf("%s\t%s,.-%o\t\t; %06o [%s]",
			   'sob', _r($wrd>>6), abs($npc-$adr), $npc, $label{$npc});
	} else {
	    $str = sprintf("%s\t%s,%s\t\t; %06o [.-%o]",
			   'sob', _r($wrd>>6), $label{$npc}, $npc, abs($npc-$adr));
	}
	$entry{$adr+2}++;
	$entry{$npc}++;

    } elsif ($wrd >= 000200 && $wrd <= 000207) { # ok
	#
	# return-from-subroutine sop single-word instruction
	#
	$str = sprintf("rts\t%s", _r($wrd>>0));

    } elsif ($wrd >= 000100 && $wrd <= 000177) { # maybe
	#
	# unconditional jump sop single/double-word instruction
	#
	$str = sprintf("%s\t%s", 'jmp', _mode($wrd>>0,$adr+2,2));
	$cnt += _eat($wrd>>0);
	if (($wrd&077) == 037) { # absolute address @#FOO
	    $entry{$wrd[$adr+2]}++;
	} elsif (($wrd&067) == 067) { # pc-relative address FOO
	    my $npc = ($adr+2 + 2 + $wrd[$adr+2]) & 0xFFFF;
	    $label{$npc} = 'L'.$label++ unless exists($label{$npc});
	    $entry{$npc}++;
	}

    } elsif ($wrd >= 004000 && $wrd <= 004777) { # maybe
	#
	# jump-to-subr dop single/double-word instruction
	#
	$str = sprintf("%s\t%s,%s", 'jsr', _r($wrd>>6), _mode($wrd>>0,$adr+2,2));
	$cnt += _eat($wrd>>0);
	if (($wrd&077) == 037) { # absolute address @#FOO
	    $entry{$wrd[$adr+2]}++;
	} elsif (($wrd&067) == 067) { # pc-relative address FOO
	    my $npc = ($adr+2 + 2 + $wrd[$adr+2]) & 0xFFFF;
	    $label{$npc} = 'L'.$label++ unless exists($label{$npc});
	    $entry{$npc}++;
	}
	$entry{$adr+2 + 2*_eat($wrd>>0)}++;

    } elsif ($wrd >= 005000 && $wrd <= 006777 || $wrd >= 0105000 && $wrd <= 0106777 ||
	     $wrd >= 000300 && $wrd <= 000377) { # maybe
	#
	# arithmetic sop single/double-word instructions
	#
	my $opc = ('ror', 'rol', 'asr', 'asl', 'mark','mfpi','mtpi','sxt',
		   'clr', 'com', 'inc', 'dec', 'neg', 'adc', 'sbc', 'tst',
		   'rorb','rolb','asrb','aslb','mtps','mfpd','mtpd','mfps',
		   'clrb','comb','incb','decb','negb','adcb','sbcb','tstb'
		   ) [ (($wrd&0100000)>>11) | (($wrd&001700)>>6) ];
	$opc = 'swab' if $wrd <= 000377;
	if ($opc eq 'mark') {
	    $str = sprintf("mark\t%o", $wrd&077);
	} else {
	    if ((($wrd>>0)&067) == 067) {
		my $ea = ($adr+2 + 2 + $wrd[$adr+2]) & 0xFFFF;
		$label{$ea} = 'L'.$label++ unless exists($label{$ea});;
	    }
	    $str = sprintf("%s\t%s", $opc, _mode($wrd>>0,$adr+2,2));
	    $cnt += _eat($wrd>>0);
	    $entry{$adr+2 + 2*_eat($wrd>>0)}++;
	}

    } elsif ($wrd >= 070000 && $wrd <= 074777) { # maybe
	#
	# arithmetic dop single/double-word instructions
	#
	my $opc = ('mul','div','ash','ashc','xor') [ ($wrd&007000)>>9 ];
	if ((($wrd>>0)&067) == 067) {
	    my $ea = ($adr+2 + 2 + $wrd[$adr+2]) & 0xFFFF;
	    $label{$ea} = 'L'.$label++ unless exists($label{$ea});;
	}
	if ($opc eq 'xor') {
	    $str = sprintf("%s\t%s,%s", $opc, _r($wrd>>6), _mode($wrd>>0,$adr+2,2));
	} else {
	    $str = sprintf("%s\t%s,%s", $opc, _mode($wrd>>0,$adr+2,2), _r($wrd>>6));
	}
	$cnt += _eat($wrd>>0);
	$entry{$adr+2 + 2*_eat($wrd>>0)}++;

    } elsif ($wrd >= 010000 && $wrd <= 067777 || $wrd >= 0110000 && $wrd <= 0167777) { # maybe
	#
	# arithmetic dop single/double/triple-word instructions
	#
	my $opc = ('xxx','mov', 'cmp', 'bit', 'bic', 'bis', 'add','xxx',
		   'xxx','movb','cmpb','bitb','bicb','bisb','sub','xxx'
		   ) [ ($wrd&0170000)>>12 ];
	if ((($wrd>>6)&067) == 067) {
	    my $ea = ($adr+2 + 2 + $wrd[$adr+2]) & 0xFFFF;
	    $label{$ea} = 'L'.$label++ unless exists($label{$ea});;
	}
	if ((($wrd>>0)&067) == 067) {
	    my $ea = ($adr+2 + 2*_eat($wrd>>6) + 2 + $wrd[$adr+2*_eat($wrd>>6)+2]) & 0xFFFF;
	    $label{$ea} = 'L'.$label++ unless exists($label{$ea});;
	}
	$str = sprintf("%s\t%s,%s",
		       $opc, _mode($wrd>>6,$adr+2,2), _mode($wrd>>0,$adr+2+2*_eat($wrd>>6),4));
	$cnt += _eat($wrd>>6) + _eat($wrd>>0);
	$entry{$adr+2 + 2*_eat($wrd>>6) + 2*_eat($wrd>>0)}++;

    } elsif ($wrd >= 0170000 && $wrd <= 0177777) { # TBD
	#
	# FPP float sop/dop single/double-word instructions
	#
	$str = 'float';
	$entry{$adr+2}++;

    } else { # ok
	#
	# all ILLEGAL opcodes (not previously decoded)
	#
	$str = 'ILLEGAL';

    }

    return ($cnt,$str);

}

#----------------------------------------------------------------------------------------------------

# convert string of byte hex characters to an array of numbers

sub hexa ($) {

    my ($dat) = @_;

    my @dat = ();
    while ($dat) { push(@dat,hex(substr($dat,0,2))); $dat = substr($dat,2); }

    return @dat;
}

#----------------------------------------------------------------------------------------------------

# trim leading/trailing spaces on a string

sub trim ($) {

    my ($str) = @_;

    $str =~ s/\s+$//;
    $str =~ s/^\s+//;
    
    return $str;
}

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

# read a record from the object file

sub read_rec ($) {

    my ($fh) = @_;

    my ($buf, $cnt, $len, $err) = (0,0,0,0);
    my @pre = ();
    my @dat = ();
    my @suf = ();

    # Object file format consists of blocks, optionally preceded, separated, and
    # followed by zeroes.  Each block consists of:
    #
    #   001		---
    #   000		 |
    #   lo(length)	 |
    #   hi(length)	 > 'length' bytes
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

    # bytes five thru end-1 are data bytes
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
    die sprintf("Error: invalid object file record format (%d)", $err) if $err;

    # compare rcv'ed checksum vs exp'ed checksum
    my $exp = &chksum(0x01, $len>>0, $len>>8, @dat);
    die sprintf("Error: Bad checksum exp=0x%02X rcv=0x%02X", $exp, $rcv) unless $exp == $rcv;

    # all is well, return the record
    return @dat;
}

#----------------------------------------------------------------------------------------------------

# the end
