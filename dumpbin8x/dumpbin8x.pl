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

# globals
my %memory = ();
my @status = ();

# loop on all input files
foreach my $filename (@ARGV) {

    # open .bin papertape image file
    printf STDERR "Processing file %s ...\n", $filename if $VERBOSE;
    unless (open(INP, "< $filename")) {
	printf STDERR "ERROR: cannot open input file %s\n", $filename;
	next;
    }
    binmode(INP);

    my ($addr,$field,$newfield,$chksum) = (0,0,0,0);
    my ($state,$hibyte,$lobyte) = ('JUNK',-1,-1);

    # process content bytes
    while (!eof(*INP) && $state ne 'DONE') {

	# get next input byte
	my $byte = get_byte(*INP);

	# RUBOUT deletes next byte
	if (is_rubout($byte)) {
	    printf STDERR " %-4s %03o\n", 'RUB', $byte if $VERBOSE;
	    $byte = get_byte(*INP);
	    printf STDERR " %-4s %03o\n", 'RUB', $byte if $VERBOSE;
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
	    ($addr,$field,$newfield,$chksum) = (0,0,0,0);
	    ($hibyte,$lobyte) = (-1,-1);
	    printf STDERR " %-4s %s\n", $state, make_str($byte) if $VERBOSE;
	} elsif ($state eq 'SKIP') {
	    # eating leader
	    if (is_leader($byte)) {
		printf STDERR " %-4s %03o\n", $state, $byte if $VERBOSE;
		next;
	    }
	    $hibyte = $byte;
	    $state = 'HI';
	    printf STDERR " %-4s %03o\n", $state, $byte if $VERBOSE;
	} elsif ($state eq 'HI') {
	    # first byte
	    $lobyte = $byte;
	    $state = 'LO';
	    printf STDERR " %-4s %03o\n", $state, $byte if $VERBOSE;
	} elsif ($state eq 'LO') {
	    # second byte
	    my $word = (($hibyte<<6) | $lobyte) & 07777;
	    if (is_leader($byte)) {
		# this is the final checksum
		my $result = sprintf("CHKSUM: Computed: %04o, input: %04o -- %s",
				     $chksum, $word, $chksum == $word ? "PASS" : "FAIL");
		printf STDERR "FILE: %s\n%s\n", $filename, $result;
		push(@status, [$filename,$result]);
		$state = 'DONE';
	    } else {
		# this is address or data
		$chksum = ($chksum + $hibyte + $lobyte) & 07777;
		if (is_address($hibyte)) {
		    # address word
		    $addr = $word;
		    printf STDERR " %-4s %04o\n", 'ADDR', $word if $VERBOSE;
		} else {
		    # data word
		    $memory{$field}{$addr} = $word;
		    $addr = ($addr+1) & 07777;
		}
		$field = $newfield;
		$hibyte = $byte;
		$state = 'HI';
		printf STDERR " %-4s %03o\n", $state, $byte if $VERBOSE;
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
    foreach my $extaddr (keys(%OVERRIDE)) {
	$memory{($extaddr>>12)&7}{$extaddr&07777} = $OVERRIDE{$extaddr}&07777;
    }
}

# generate output
if (1) {
    # header
    foreach my $entry (@status) {
	if ($VERILOG) {
	    printf STDOUT "    // File: %s; Status: %s\n", $$entry[0], $$entry[1];
	} else {
	    printf STDOUT "# File: %s; Status: %s\n", $$entry[0], $$entry[1];
	}
    }
    if ($VERILOG) {
	printf STDOUT "    //\n";
    } else {
	printf STDOUT "#\n";
    }
    # body
    foreach my $field (sort({$a<=>$b}keys(%memory))) {
	foreach my $addr (sort({$a<=>$b}keys(%{$memory{$field}}))) {
	    my $word = $memory{$field}{$addr};
	    if ($VERILOG) {
		printf STDOUT "    memory[15'o%o%04o] = 12'o%04o;", $field, $addr, $word;
		printf STDOUT "    // %s", decode_inst($word, $addr) if $DISASSEMBLY;
		printf STDOUT "\n";
	    } else {
		printf STDOUT "%o%04o/%04o", $field, $addr, $word;
		printf STDOUT "   %s", decode_inst($word, $addr) if $DISASSEMBLY;
		printf STDOUT "\n";
	    }
	}
    }
    # trailer
    if ($VERILOG) {
	printf STDOUT "    //\n    // the end\n";
    } else {
	printf STDOUT "#\n# the end\n";
    }
}

# done
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
    my @opc = ( "AND", "TAD", "ISZ", "DCA", "JMS", "JMP", "IOT", "OPR" );

    if ($inst <= 05777) { # 0..5 memory reference

	# compute address as either on page 0 or on current page
	my $fld = ($addr>>12)&07;
	my $tgt = ($inst & 0200) == 0200 ? (($addr & 07600)|($inst & 00177)) : ($inst & 00177);
	$str = sprintf("%s%s %o", $opc[($inst>>9)&07], ($inst & 00400) == 0400 ? " I" : "", $tgt);
	if ($inst & 0400) {
	    # indirect
	    $str = sprintf("%-12s ea=0%04o", $str, $memory{$fld}{$tgt}) if exists $memory{$fld}{$tgt};
	} else {
	    # direct
	    $str = sprintf("%-12s ea=0%04o", $str, $tgt) if  exists $memory{$fld}{$tgt};
	}

    } elsif (($inst & 07000) == 06000) { # 6 i/o transfer

	$str = sprintf("IOT %02o,%01o", ($inst>>3)&077, $inst&07);

    } elsif (($inst & 07400) == 07000) { # 7 operate group 1

	# sequence 1
	if (($inst & 00200) == 00200) { $str .= " CLA"; }
	if (($inst & 00100) == 00100) { $str .= " CLL"; }
	# sequence 2
	if (($inst & 00040) == 00040) { $str .= " CMA"; }
	if (($inst & 00020) == 00020) { $str .= " CML"; }
	# sequence 3
	if (($inst & 00001) == 00001) { $str .= " IAC"; }
	# sequence 4
	if (($inst & 00016) == 00010) { $str .= " RAR"; }
	if (($inst & 00016) == 00004) { $str .= " RAL"; }
	if (($inst & 00016) == 00012) { $str .= " RTR"; }
	if (($inst & 00016) == 00006) { $str .= " RTL"; }
	if (($inst & 00016) == 00002) { $str .= " BSW"; }
	# else
	if (($inst & 00377) == 00000) { $str .= " NOP"; }
	# fixup
	if ($str eq " CMA IAC") { $str = " CIA"; }
	if ($str eq " CLL CML") { $str = " STL"; }
	if ($str eq " CLA RAL") { $str = " GLK"; }
	# default
	if ($str eq "") { $str = sprintf("%o", $inst); }

    } elsif (($inst & 07401) == 07400) { # 7 operate group 2

	# sequence 1
	if (($inst & 00110) == 00100) { $str .= " SMA"; }
	if (($inst & 00050) == 00040) { $str .= " SZA"; }
	if (($inst & 00030) == 00020) { $str .= " SNL"; }
	if (($inst & 00110) == 00110) { $str .= " SPA"; }
	if (($inst & 00050) == 00050) { $str .= " SNA"; }
	if (($inst & 00030) == 00030) { $str .= " SZL"; }
	if (($inst & 00170) == 00010) { $str .= " SKP"; }
	# sequence 2
	if (($inst & 00200) == 00200) { $str .= " CLA"; }
	# sequence 3
	if (($inst & 00004) == 00004) { $str .= " OSR"; }
	if (($inst & 00002) == 00002) { $str .= " HLT"; }
	# fixup
	if ($str eq " CLA OSR") { $str = " LAS"; }
	# default
	if ($str eq "") { $str = sprintf("%o", $inst); }

    } elsif (($inst & 07401) == 07401) { # 7 mq microinstructions

	# sequence 1
	if (($inst & 00200) == 00200) { $str .= " CLA"; }
	# sequence 2
	if (($inst & 00100) == 00100) { $str .= " MQA"; }
	if (($inst & 00020) == 00020) { $str .= " MQL"; }
	# fixup
	if (($inst & 07777) == 07621) { $str  = " CAM"; }
	if (($inst & 07777) == 07521) { $str  = " SWP"; }
	if (($inst & 07777) == 07701) { $str  = " ACL"; }
	if (($inst & 07777) == 07721) { $str  = " CLA SWP"; }
	# garbage
	if (($inst & 00056) != 00000) { $str  = ""; }
	# default
	if ($str eq "") { $str = sprintf("%o", $inst); }

    }

    # remove leading spaces, if any
    $str =~ s/^\s+//;
    return $str;

}

# the end
