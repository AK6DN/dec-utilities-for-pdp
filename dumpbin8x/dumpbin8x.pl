#!/usr/bin/perl -w
#!/usr/local/bin/perl -w

require 5.005;

# add additional search libraries
BEGIN { unshift(@INC, $ENV{'PERL5LIB'}) if exists($ENV{'PERL5LIB'}); }
	
# options
use strict;

# external modules
use Getopt::Long;
use Pod::Text;
use FindBin;

# generic defaults
my $VERSION = 'v0.0d0'; # version of code
my $HELP = 0; # set to 1 for man page output
my $DEBUG = 0; # set to 1 for debug messages
my $VERBOSE = 0; # set to 1 for verbose messages

# specific defaults
my $VERILOG = 0; # set to 1 for verilog format output
my %OVERRIDE = (); # override values
my $DISASSEMBLY = 1; # set to 1 for disassembled output

# process command line arguments
my $NOERROR = GetOptions( "help!"	 => \$HELP,
			  "debug!"	 => \$DEBUG,
			  "verbose!"	 => \$VERBOSE,
			  "verilog"	 => \$VERILOG,
			  "disassembly!" => \$DISASSEMBLY,
			  "override=s"   => sub { foreach my $pair (split(',',$_[1])) { my ($a,$d) = split(':',$pair); $OVERRIDE{oct($a)} = oct($d); } },
			  );

# init
$VERBOSE = 1 if $DEBUG; # debug implies verbose messages

# say hello
printf STDERR "%s %s by Don North (perl %g)\n", $0, $VERSION, $] if $VERBOSE;

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
       --[no]help              output manpage and exit
       --[no]debug             enable debug mode
       --[no]verbose           verbose status reporting
       --verilog               verilog format output
       --override=A:D,...      override addr/data values
       --[no]disassembly       disassembly comments
       FILENAME                a filename...
EOF
    # exit if errors...
    die "Aborted due to command line errors.\n";
}

# ----------------------------------------------------------------------------------------------

# loop on all input files
foreach my $filename (@ARGV) {

    # open .bin papertape image file
    printf STDERR "Processing file %s ...\n", $filename if $VERBOSE;
    unless (open(INP, "< $filename")) {
	printf STDERR "ERROR: cannot open input file %s\n", $filename;
	next;
    }
    binmode(INP);

    # file source header
    if ($VERILOG) {
	printf STDOUT "    //\n";
	printf STDOUT "    // File: %s\n", $filename;
	printf STDOUT "    //\n";
    }

    my ($addr,$field,$newfield,$chksum,$seen) = (0,0,0,0,0);
    my ($state,$hibyte,$lobyte) = ('JUNK',-1,-1);

    # process content bytes
    while (!eof(*INP) && $state ne 'DONE') {

	# get next input byte
	my $byte = get_byte(*INP);

	# RUBOUT deletes next byte
	if (is_rubout($byte)) {
	    printf STDOUT "    // " if $VERILOG && $VERBOSE;
	    printf STDOUT " %-4s %03o\n", 'RUB', $byte if $VERBOSE;
	    $byte = get_byte(*INP);
	    printf STDOUT "    // " if $VERILOG && $VERBOSE;
	    printf STDOUT " %-4s %03o\n", 'RUB', $byte if $VERBOSE;
	    $byte = get_byte(*INP);
	}
	
	# check for field set (not included in checksum)
	if (is_field($byte)) {
	    $newfield = ($byte>>3)&7;
	    next;
	}

	# make a printable string out of a character
	sub make_str ($) { my ($t) = @_; return $t < 0x20 || $t > 0x7E ? sprintf("%03o",$t) : sprintf("'%c'",$t); }

	# state machine
	if ($state eq 'JUNK') {
	    # skipping junk
	    if (is_leader($byte)) { $state = 'SKIP'; }
	    ($addr,$field,$newfield,$chksum,$seen) = (0,0,0,0,0);
	    ($hibyte,$lobyte) = (-1,-1);
	    printf STDOUT "    // " if $VERILOG && $VERBOSE;
	    printf STDOUT " %-4s %s\n", $state, make_str($byte) if $VERBOSE;
	} elsif ($state eq 'SKIP') {
	    # eating leader
	    if (is_leader($byte)) {
		printf STDOUT "    // " if $VERILOG && $VERBOSE;
		printf STDOUT " %-4s %03o\n", $state, $byte if $VERBOSE;
		next;
	    }
	    $hibyte = $byte;
	    $state = 'HI';
	    printf STDOUT "    // " if $VERILOG && $VERBOSE;
	    printf STDOUT " %-4s %03o\n", $state, $byte if $VERBOSE;
	} elsif ($state eq 'HI') {
	    # first byte
	    $lobyte = $byte;
	    $state = 'LO';
	    printf STDOUT "    // " if $VERILOG && $VERBOSE;
	    printf STDOUT " %-4s %03o\n", $state, $byte if $VERBOSE;
	} elsif ($state eq 'LO') {
	    # second byte
	    my $word = (($hibyte<<6) | $lobyte) & 07777;
	    if (is_leader($byte)) {
		# this is the final checksum
		printf STDOUT "    //\n    // " if $VERILOG;
		printf STDOUT "CHKSUM: Computed: %04o, input: %04o -- %s\n",
		           $chksum, $word, $chksum == $word ? "PASS" : "FAIL";
		printf STDOUT "    //\n" if $VERILOG;
		$state = 'DONE';
	    } else {
		# this is address or data
		$chksum = ($chksum + $hibyte + $lobyte) & 07777;
		if (is_address($hibyte)) {
		    # address word
		    printf STDOUT "    //\n" if $VERILOG && $seen;
		    $addr = $word;
		    $seen = 0;
		    printf STDOUT "    // " if $VERILOG && $VERBOSE;
		    printf STDOUT " %-4s %04o\n", 'ADDR', $word if $VERBOSE;
		} else {
		    # data word
		    if ($VERILOG) {
			printf STDOUT "    memory[15'o%o%04o] = 12'o%04o;", $field, $addr, $word;
			printf STDOUT "    // %s", decode_inst($word, $addr) if $DISASSEMBLY;
			printf STDOUT "\n";
		    } else {
			printf STDOUT "%o%04o/%04o", $field, $addr, $word;
			printf STDOUT "   %s", decode_inst($word, $addr);
			printf STDOUT "\n";
		    }
		    $addr = ($addr+1) & 07777;
		    $seen = 1;
		    printf STDOUT "    // " if $VERILOG && $VERBOSE;
		    printf STDOUT " %-4s %04o\n", 'DATA', $word if $VERBOSE;
		}
		printf STDOUT "    // " if $VERILOG && $VERBOSE;
		printf STDOUT " %-4s %o\n", 'FLD', $newfield if $field != $newfield && $VERBOSE;
		$field = $newfield;
		$hibyte = $byte;
		$state = 'HI';
		printf STDOUT "    // " if $VERILOG && $VERBOSE;
		printf STDOUT " %-4s %03o\n", $state, $byte if $VERBOSE;
	    }
	} else { # invalid transition
	    $state = '????';
	    die "invalid transition";
	}

    } # while $state

    close(INP);

} # foreach $filename

# process memory override values
if (keys(%OVERRIDE) > 0) {
    printf STDOUT "    // OVERRIDE values\n    //\n" if $VERILOG;
    foreach my $extaddr (keys(%OVERRIDE)) {
	my $word = $OVERRIDE{$extaddr};
	my $field = ($extaddr>>12)&07;
	my $addr = $extaddr&07777;
	if ($VERILOG) {
	    printf STDOUT "    memory[15'o%o%04o] = 12'o%04o;", $field, $addr, $word;
	    printf STDOUT "    // %s", decode_inst($word, $addr) if $DISASSEMBLY;
	    printf STDOUT "\n";
	} else {
	    printf STDOUT "%o%04o/%04o", $field, $addr, $word;
	    printf STDOUT "   %s", decode_inst($word, $addr);
	    printf STDOUT "\n";
	}
    }
    printf STDOUT "    //\n" if $VERILOG;
}

exit;

# ----------------------------------------------------------------------------------------------

# read next byte from input file, honor pushbacks

my @buffer = ();

sub get_byte {

    local (*FILE) = @_;
	   
    my ($cnt,$byte) = (-1,-1);

    if (defined($buffer[fileno(FILE)]) && @{$buffer[fileno(FILE)]}) {

	# prior pushback data exists, use it
	$byte = pop(@{$buffer[fileno(FILE)]});

    } else {

	# no prior pushback data exists, must do a file read
	$cnt = read(FILE, $byte, 1);
	$byte = !defined($cnt) || $cnt != 1 ? -1 : ord($byte);

    }

    printf STDOUT "get_char: byte=%03o char='%s' cnt=%d\n", $byte, chr($byte), $cnt if $DEBUG;

    # printf STDERR "|%s|\n", join('',map($byte&(1<<(7-$_))?'*':'.',(0..7))) if $DEBUG;

    return $byte;

}

# push back a byte to an input file

sub unget_byte {

    my ($byte) = shift;
    local (*FILE) = shift;
	   
    push(@{$buffer[fileno(FILE)]}, $byte);

    return $byte;
    
}

# ----------------------------------------------------------------------------------------------

# paper tape format support routines

sub is_leader  { my ($c) = @_; return ($c & 0377) == 0200; }
sub is_field   { my ($c) = @_; return ($c & 0307) == 0300; }
sub is_address { my ($c) = @_; return ($c & 0300) == 0100; }
sub is_data    { my ($c) = @_; return ($c & 0300) == 0000; }
sub is_rubout  { my ($c) = @_; return ($c & 0377) == 0377; }

# ----------------------------------------------------------------------------------------------

# pdp-8 instruction disassembler

sub decode_inst {

    my ($inst, $addr) = @_;

    my $str = '';
    my @opc = ( "and", "tad", "isz", "dca", "jms", "jmp", "iot", "opr" );

    if ($inst <= 05777) { # 0..5 memory reference

	$str = sprintf("%s%s %o", $opc[($inst>>9)&07],
		       ($inst & 00400) ? " i" : "",
		       ($inst & 00200) ? ($addr & 07600) | ($inst & 00177) : ($inst & 00177));

    } elsif (($inst & 07000) == 06000) { # 6 i/o transfer

	$str = sprintf("iot %o,%o", ($inst>>3)&077, $inst&07);

    } elsif (($inst & 07400) == 07000) { # 7 operate group 1

	# sequence 1
	if (($inst & 00200) == 00200) { $str .= " cla"; }
	if (($inst & 00100) == 00100) { $str .= " cll"; }
	# sequence 2
	if (($inst & 00040) == 00040) { $str .= " cma"; }
	if (($inst & 00020) == 00020) { $str .= " cml"; }
	# sequence 3
	if (($inst & 00001) == 00001) { $str .= " iac"; }
	# sequence 4
	if (($inst & 00016) == 00010) { $str .= " rar"; }
	if (($inst & 00016) == 00004) { $str .= " ral"; }
	if (($inst & 00016) == 00012) { $str .= " rtr"; }
	if (($inst & 00016) == 00006) { $str .= " rtl"; }
	if (($inst & 00016) == 00002) { $str .= " bsw"; }
	# else
	if (($inst & 00377) == 00000) { $str .= " nop"; }
	# done

    } elsif (($inst & 07401) == 07400) { # 7 operate group 2

	# sequence 1
	if (($inst & 00110) == 00100) { $str .= " sma"; }
	if (($inst & 00050) == 00040) { $str .= " sza"; }
	if (($inst & 00030) == 00020) { $str .= " snl"; }
	if (($inst & 00110) == 00110) { $str .= " spa"; }
	if (($inst & 00050) == 00050) { $str .= " sna"; }
	if (($inst & 00030) == 00030) { $str .= " szl"; }
	if (($inst & 00170) == 00010) { $str .= " skp"; }
	# sequence 2
	if (($inst & 00200) == 00200) { $str .= " cla"; }
	# sequence 3
	if (($inst & 00004) == 00004) { $str .= " osr"; }
	if (($inst & 00002) == 00002) { $str .= " hlt"; }
	# done

    } elsif (($inst & 07401) == 07401) { # 7 mq microinstructions

	# sequence 1
	if (($inst & 00200) == 00200) { $str .= " cla"; }
	# sequence 2
	if (($inst & 00100) == 00100) { $str .= " mqa"; }
	if (($inst & 00020) == 00020) { $str .= " mql"; }
	# sequence 3
	# else
	if (($inst & 00376) == 00000) { $str .= " nop"; }
	# done

    }

    # remove leading spaces, if any
    $str =~ s/^\s+//;
    return $str;

}

# the end
