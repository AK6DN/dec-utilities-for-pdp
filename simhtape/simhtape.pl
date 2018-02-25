#!/usr/bin/perl -w
#!/usr/local/bin/perl -w

# options
use strict;
	
# external standard modules
use Getopt::Long;
use Pod::Text;
use FindBin;
use FileHandle;
use Time::Local;
use File::Spec;
use File::Basename;
use File::Path qw( make_path );

# external local modules search path
BEGIN { unshift(@INC, $FindBin::Bin);
        unshift(@INC, '.'); }

# external local modules

# generic defaults
my $VERSION = 'v1.0'; # version of code
my $HELP = 0; # set to 1 for man page output
my $DEBUG = 0; # set to >=1 for debug messages
my $VERBOSE = 0; # set to 1 for verbose messages

# specific defaults
my $TAPE = 'NONE'; # set to filename of .tap file
my $MODE = 'NONE'; # set to DUMP, EXTRACT, INSERT
my $PATH = '.'; # path to directory for EXTRACT of files
my $BLOCKSIZE = 512; # default tape blocksize
my $TEXTMODE = 1; # set for text files, cleared for binary files

# process command line arguments
my $NOERROR = GetOptions( "help"        => \$HELP,
			  "debug:1"     => \$DEBUG,
			  "verbose"     => \$VERBOSE,
			  "blocksize=i" => \$BLOCKSIZE,
			  "binarymode"  => sub { $TEXTMODE = 0; },
			  "textmode"    => sub { $TEXTMODE = 1; },
			  "tape=s"      => \$TAPE,
			  "dump"        => sub { $MODE = 'DUMP'; },
			  "extract:s"   => sub { $MODE = 'EXTRACT'; $PATH = $_[1] if $_[1]; },
			  "insert"      => sub { $MODE = 'INSERT'; },
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
	&& $TAPE ne 'NONE'
	&& $MODE ne 'NONE'
    ) {
    printf STDERR "%s %s (perl %g)\n", $0, $VERSION, $];
    print STDERR "Usage: $0 [options...] arguments\n";
    print STDERR <<"EOF";
       --help               output manpage and exit
       --debug=N            enable debug mode 'N'
       --verbose            verbose status reporting
       --binarymode         transfer files as binary data
       --textmode           transfer files as ascii text
       --blocksize=N        tape blocksize, default 512 bytes
       --tape=FILENAME      name of SIMH .tap file
       --dump               dump tape contents
       --extract[=TOPATH]   extract tape contents to files in path
       --insert FILES...    insert files to tape
EOF
    # exit if errors...
    die "Aborted due to command line errors.\n";
}

################################################################################

# global data

my @r50asc = split('', ' ABCDEFGHIJKLMNOPQRSTUVWXYZ$.?0123456789');
my %irad50 = map {$r50asc[$_],$_} (0..$#r50asc);

################################################################################

# process tape file

if ($MODE eq 'DUMP') {
    &_dump_tape($TAPE);
} elsif ($MODE eq 'EXTRACT') {
    &_read_tape($TAPE);
} elsif ($MODE eq 'INSERT') {
    &_write_tape($TAPE, \@ARGV);
}

exit;

################################################################################

# dump a full tape

sub _dump_tape {

    my ($tape) = @_;

    # always do some printing
    $VERBOSE = 1;
    printf STDERR "Dumping tape image file '%s' ...\n", $tape if $VERBOSE;

    # init some stats
    my $tapemark = 0;
    my %bytecount = ();
    my %reccount = ();

    # input file descriptor
    if (open(my $ifh, '<', $tape)) {

	# some support code
	sub _dump ($$) { my ($p,$s) = @_; return join(',',map(sprintf("%02X",$_),unpack($p,$s))); }

	# loop over whole tape image file
	while (1) {
	    my ($pre,$buf,$suf) = (undef,undef,undef);

	    # read the 4B record length, little endian
	    my $prelen = &_read($ifh, 4, \$pre);
	    last if $prelen == -1 || $prelen == 0; # exit on EOF, no more data
	    my $preval = unpack('V', $pre);
	    printf STDERR "\n  prefix: len=%d val=%d pre=[%s]\n",
	                  $prelen, $preval, &_dump('C*',$pre) if $DEBUG >= 1;

	    # a value of zero is a tape mark
	    if ($prelen == 4 && $preval == 0) {
		printf STDERR "  *** TAPE MARK ***\n" if $VERBOSE;
		next;
	    }

	    # a value of -1 indicates EOF, as well as two sequential tapemarks
	    if ($tapemark == 2 || $prelen == 4 && $preval == 0xFFFFFFFF) {
		printf STDERR "  *** TAPE EOF ***\n" if $VERBOSE;
		my $buflen = &_read($ifh, 1<<20, \$buf);
		printf STDERR "  extra: len=%d buf=[%s]\n",
		              $buflen, &_dump('C*',$buf) unless $buflen == 0;
		last;
	    }

	    # reset tapemark flag
	    $tapemark = 0;

	    # read next data record depending upon prefix length
	    my $buflen = &_read($ifh, $preval, \$buf);
	    if ($VERBOSE) {
		printf STDERR "  buffer: len=%d buf=[%s,...]\n",
		              $buflen, &_dump('C20',$buf) if $DEBUG == 2;
		printf STDERR "  buffer: len=%d buf=[%s]\n",
		              $buflen, &_dump('C*',$buf) if $DEBUG >= 3;
		if ($buflen == 80) {
		    # will be an ANSI header record
		    printf STDERR "  alabel: [%s]\n", $buf;
		}
	    }

	    # count records and data bytes
	    $reccount{$buflen} += 1;
	    $bytecount{$buflen} += $buflen;

	    # SIMH format has a record trailer
	    my $suflen = &_read($ifh, 4, \$suf);
	    my $sufval = unpack('V', $suf);
	    printf STDERR "  suffix: len=%d val=%d suf=[%s]\n",
	                  $suflen, $sufval, &_dump('C*',$suf) if $DEBUG >= 1;

	    # check for valid format
	    next if $prelen == 4 && $suflen == 4 && $preval == $sufval && $preval == $buflen;

	    # nope, something is unexpected
	    printf STDERR "  format error: prelen=%d suflen=%d preval=%d sufval=%d buflen=%d\n",
	                  $prelen, $suflen, $preval, $sufval, $buflen;

	}

	# we be done
	close($ifh);
    }
    
    # overall counts
    printf STDERR "\nDone\n" if $VERBOSE;
    foreach my $i (sort({$a<=>$b}keys(%reccount))) {
	printf STDERR "Saw %d records of length %d bytes; total %d bytes\n",
 	              $reccount{$i},$i,$bytecount{$i} if $VERBOSE;
    }

    return;
}

################################################################################

# read a full tape

sub _read_tape {

    my ($tape) = @_;

    printf STDERR "Reading tape image file '%s' ...\n", $tape if $VERBOSE;

    # init some stats
    my $istextmode = $TEXTMODE;
    my $tapemark = 0;
    my $vollabel = '';
    my $filename = '';
    my $filedate = '';
    my $ofh = undef;

    # input file descriptor
    if (open(my $ifh, '<', $tape)) {

	# loop over whole tape image file
	while (1) {
	    my ($pre,$buf,$suf) = (undef,undef,undef);

	    # read the 4B record length, little endian
	    my $prelen = &_read($ifh, 4, \$pre);
	    last if $prelen == -1 || $prelen == 0; # exit on EOF, no more data
	    my $preval = unpack('V', $pre);

	    # a value of zero is a tape mark
	    next if $prelen == 4 && $preval == 0;

	    # a value of -1 indicates EOF, as well as two sequential tapemarks
	    last if $tapemark == 2 || $prelen == 4 && $preval == 0xFFFFFFFF;

	    # reset tapemark flag
	    $tapemark = 0;

	    # read next data record depending upon prefix length
	    my $buflen = &_read($ifh, $preval, \$buf);

	    # process header vs data vs trailer
	    if ($buflen == 80 && substr($buf, 0, 4) eq 'HDR1') {
		# HDR1 has filename
		$filename = &trim(substr($buf, 4, 17));
		$filedate = substr($buf, 42, 5);
		printf STDERR "Extracting file '%s' (%s)\n", $filename, $filedate if $VERBOSE;
		printf STDERR "  %s file=%s date=%s\n", substr($buf,0,4), $filename, $filedate if $DEBUG;
		make_path($PATH);
		open($ofh, '>', File::Spec->catfile($PATH, $filename)) || die;
		$istextmode = $TEXTMODE;
	    } elsif ($buflen == 80 && substr($buf, 0, 4) eq 'HDR2') {
		# HDR2 info we don't use
	    } elsif ($buflen == 80 && substr($buf, 0, 4) eq 'EOF1') {
		# EOF1 info we don;t use except to close file
		printf STDERR "  %s file=%s close\n", substr($buf,0,4), $filename if $DEBUG;
		# done
		close($ofh);
		# set the access and modification times from the source media
		utime(&_yyddd2stamp($filedate), &_yyddd2stamp($filedate), File::Spec->catfile($PATH, $filename));
	    } elsif ($buflen == 80 && substr($buf, 0, 4) eq 'EOF2') {
		# EOF2 info we don't use
	    } elsif ($buflen == 80 && substr($buf, 0, 4) eq 'VOL1') {
		# VOL1 has volume label
		$vollabel = substr($buf, 4, 6);
		printf STDERR "  %s label=%s\n", substr($buf,0,4), $vollabel if $DEBUG;
	    } else {
		# prune trailing zero bytes in record, if TEXTMODE
		my $skplen = 0;
		if ($istextmode) { while (ord(substr($buf,$buflen-$skplen-1,1)) == 0 && $skplen < $buflen) { ++$skplen; } }
		my $wrote = &_write($ofh, $buflen-$skplen, \$buf);
		printf STDERR "  DATA %d (%d)\n", $wrote, -$skplen if $DEBUG;
	    }

	    # SIMH format has a record trailer
	    my $suflen = &_read($ifh, 4, \$suf);
	    my $sufval = unpack('V', $suf);

	    # check for valid format
	    next if $prelen == 4 && $suflen == 4 && $preval == $sufval && $preval == $buflen;

	    # nope, something is unexpected
	    printf STDERR "  format error: prelen=%d suflen=%d preval=%d sufval=%d buflen=%d\n",
	                  $prelen, $suflen, $preval, $sufval, $buflen;

	}

	# we be done
	close($ifh);
    }

    return;
}

################################################################################

# write a full tape

sub _write_tape {

    my ($tape,$files) = @_;

    printf STDERR "Writing tape image file '%s' ...\n", $tape if $VERBOSE;

    # local state
    my $vollab = 'RSTS';
    my $opsys = 'DECRSTS/E';
    my $buf = undef;

    # output file descriptor
    if (open(my $ofh, '>', $tape)) {

	# write volume label
	$buf = sprintf("%-4s%-6s%-1s%-26s%-14s%-28s%-1s",
		       'VOL1', $vollab, '', '', 'D%B44310100101', '', '3');
	&_write_record($ofh, $buf);

	# locals
	my $filenumb = 0;

	# loop over all files
	foreach my $fullname (@$files) {

	    printf STDERR "Copy file '%s' ...\n", $fullname if $VERBOSE;

	    # locals
	    my $blocks = 0; # count blocks written per file

	    # open data file for reading
	    if (open(my $ifh, '<', $fullname)) {

		# strip any leading path from name, make uppercase
		my $filename = uc((File::Spec->splitpath($fullname))[-1]);

		# last modified date for the file to YYDDD format
		my ($dd,$mm,$yy) = (localtime((stat($ifh))[9]))[3,4,5];
		my $filedate = &_ddmmyy2yyddd($dd,$mm+1,$yy);
		printf STDERR "filename='%s' filedate=%05d datestamp=%02d/%02d/%02d\n",
		              $filename, $filedate, $dd, $mm+1, $yy+1900 if $DEBUG;

		# write header1 label
		$buf = sprintf("%-4s%-17s%-6s%04d%04d%04d%02d %05d %05d%1s%06d%-13s%-7s",
			       'HDR1', $filename, $vollab, 1, ++$filenumb, 1, 0,
			       $filedate, $filedate, '', 0, $opsys, '');
		&_write_record($ofh, $buf);

		# write header2 label
		$buf = sprintf("%-4s%1s%05d%05d%21s%1s%13s%02d%28s",
			       'HDR2', 'U', $BLOCKSIZE, 0, '', 'M', '', 0, '');
		&_write_record($ofh, $buf);

		# write a record mark
		&_write_mark($ofh, 0);

		# copy all the data, blocked to $BLOCKSIZE byte records
		while ((my $count = &_read($ifh, $BLOCKSIZE, \$buf)) > 0) {

		    # zero extend the record to $BLOCKSIZE if too short
		    $buf .= "\x00" x ($BLOCKSIZE - $count) if $count < $BLOCKSIZE;

		    # write the data block
		    &_write_record($ofh, $buf);

		    # count blocks
		    ++$blocks;
		}

		# write a record mark
		&_write_mark($ofh, 0);

		# write trailer1 label
		$buf = sprintf("%-4s%-17s%-6s%04d%04d%04d%02d %05d %05d%1s%06d%-13s%-7s",
			       'EOF1', $filename, $vollab, 1, $filenumb, 1, 0,
			       $filedate, $filedate, '', $blocks, 'DECRSTS/E', '');
		&_write_record($ofh, $buf);

		# write trailer2 label
		$buf = sprintf("%-4s%1s%05d%05d%21s%1s%13s%02d%28s",
			       'EOF2', 'U', $BLOCKSIZE, 0, '', 'M', '', 0, '');
		&_write_record($ofh, $buf);

		# write a record mark
		&_write_mark($ofh, 0);

		close($ifh);
	    }
		
	} # foreach my $filename

	# write an end of media as two consecutive record marks
	&_write_mark($ofh, 0);
	&_write_mark($ofh, 0);

	# we be done
	close($ofh);
    }

    return;
}

################################################################################

# read LENGTH bytes from FH to BUFFER

sub _read {

    my ($fh, $length, $buffer) = @_;

    my $offset = 0;
    $$buffer = '';
    while ($length > 0) {
	my $count = sysread($fh, $$buffer, $length, $offset);
	return -1 unless defined($count);
	return length($$buffer) if $count == 0;
	$length -= $count;
	$offset += $count;
    }

    return length($$buffer);

}

################################################################################

# write LENGTH bytes from BUFFER to FH

sub _write {

    my ($fh, $length, $buffer) = @_;

    my $offset = 0;
    while ($length > 0) {
	my $count = syswrite($fh, $$buffer, $length, $offset);
	return -1 unless defined($count);
	$length -= $count;
	$offset += $count;
    }

    return $offset;

}

################################################################################

# write a formatted .tap tape mark

sub _write_mark {

    my ($fh, $value) = @_;

    my $received;
    my $expected;
    my $record = pack('V', $value);

    # write 4byte tape mark record
    $expected = length($record);
    $received = &_write($fh, $expected, \$record);
    printf STDERR "Warning: tape mark write error; expected=%d, received=%d\n",
                  $expected, $received unless $expected == $received;

    return;
}

################################################################################

# write a formatted .tap data record

sub _write_record {

    my ($fh, $record) = @_;

    my $received;
    my $expected;
    my $header = pack('V', length($record));

    # write 4byte record header (length of data record, little endian)
    $expected = length($header);
    $received = &_write($fh, $expected, \$header);
    printf STDERR "Warning: header write error; expected=%d, received=%d\n",
                  $expected, $received unless $expected == $received;

    # write actual data record, as byte stream
    $expected = length($record);
    $received = &_write($fh, $expected, \$record);
    printf STDERR "Warning: record write error; expected=%d, received=%d\n",
                  $expected, $received unless $expected == $received;

    # write 4byte record trailer (length of data record, little endian)
    $expected = length($header);
    $received = &_write($fh, $expected, \$header);
    printf STDERR "Warning: trailer write error; expected=%d, received=%d\n",
                  $expected, $received unless $expected == $received;

    return;
}

################################################################################

# rad50 decoder

sub rad50dec {
    my $str = '';
    foreach my $word (@_) {
	my $trip = '';
	foreach my $n (1..3) {
	    my $char = $word % 40;
	    $word = ($word - $char) / 40;
	    $trip = $r50asc[$char] . $trip;
	}
	$str .= $trip;
    }
    return $str;
}

################################################################################

# rad50 encoder

sub rad50enc {
    my ($str) = join('',@_);
    $str .= ' ' x (3 - length($str) % 3) if length($str) % 3;
    my @out = ();
    while (length($str)) {
	my $word = 0;
	foreach my $char (split('', substr($str,0,3,''))) {
	    $word *= 40;
	    $word += exists($irad50{$char}) ? $irad50{$char} : $irad50{'?'};
	}
	push @out, $word;
    }
    return pack 'n*', @out;
}

################################################################################

# space trim

sub trim {
    my ($str) = join('',@_);
    $str =~ s/\s+$//g;
    return $str;
}

################################################################################

# Date (dd[1-31],mm[1-12],yy[00-199]) to DayOfYear (yyddd)

sub _ddmmyy2yyddd {

    my ($dom,$mon,$year) = @_;

    # correct year for various formats
    $year += 1900;
### $year = 1999 if $year >= 2000;

    # table of day-of-year offsets per month
    my @doy = (0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334);

    # correct for leap year
    my $leap = &_isleapyear($year) && $doy[$mon-1] >= 59 ? 1 : 0;

    # return encoded date word
    return ($year%100)*1000 + $doy[$mon-1] + $dom + $leap;
}

################################################################################

# DayOfYear (yyddd) to unix timestamp

sub _yyddd2stamp {

    my ($date) = @_;

    my $year = int($date/1000)+1900; $year += 100 if $year <= 1949;
    my $doy = $date%1000;

    my @dpm = (31,28,31, 30,31,30, 31,31,30, 31,30,31); # days per month
    my @mon = ('JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'); # names
    $dpm[1]++ if &_isleapyear($year);                   # fixup FEB leap year
    
    # turn day-of-year into day-of-month and month-of-year
    my $mon = 0; while ($mon <= $#mon) { last if $doy <= $dpm[$mon]; $doy -= $dpm[$mon++]; }

    # range check day
    $doy = 1 if $doy < 1;
    $doy = $dpm[$mon] if $doy > $dpm[$mon];

    # return a system timestamp as 12 noon on the given date
    return timelocal(0,0,12, $doy,$mon,$year);
}

################################################################################

# leap year routine

sub _isleapyear {

    my ($year) = @_;

    return (($year % 4 == 0) && ($year % 100 != 0)) || ($year % 400 == 0);
}

################################################################################

# the end
