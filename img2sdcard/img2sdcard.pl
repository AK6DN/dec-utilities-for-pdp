#!/usr/bin/perl -w
#!/usr/local/bin/perl -w

# options
use strict;

# external global modules
use Getopt::Long;
use Pod::Text;
use FindBin;
use FileHandle;
use File::Copy;
use File::Compare;
use POSIX;
use Expect;

# external local modules search path
BEGIN { unshift(@INC, $FindBin::Bin);
        unshift(@INC, '.'); }

# external local modules

# defaults
my $VERSION = 'v1.0'; # version of code
my $HELP = 0; # set to 1 for man page output
my $DEBUG = 0; # set to 1 for debug messages
my $VERBOSE = 0; # set to 1 for verbose messages

# arguments
my $XMLFILE = undef; # define for XML file output
my $DEVICE = undef; # define for device selection as /dev/DEVICE
my $SLICE = undef; # define for device selection as $DEVICE.$SLICE
my $SCSI = undef; # list of scsi IDs per partition
my $READFILE = undef; # image file to read
my $WRITEFILE = undef; # image file to write
my $COMPAREFILE = undef; # image file to compare
my $PARTITIONS = undef; # list of data partitions to create
my $BOARDREV = 5; # board revision, 5 or 6

# process command line arguments
my $NOERROR = GetOptions( "help!"	  => \$HELP,
			  "debug!"	  => \$DEBUG,
			  "verbose!"	  => \$VERBOSE,
			  "xmlfile=s"     => \$XMLFILE,
			  "readfile=s"    => \$READFILE,
			  "writefile=s"   => \$WRITEFILE,
			  "comparefile=s" => \$COMPAREFILE,
			  "device=s"      => \$DEVICE,
			  "slice=i"       => \$SLICE,
			  "scsi=s"        => \$SCSI,
			  "partitions=s"  => \$PARTITIONS,
			  "boardrev=i"    => \$BOARDREV,
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

# check for errors
$NOERROR = 0 if $BOARDREV < 5 || $BOARDREV > 6;

# check for correct arguments present, print usage if errors
unless ($NOERROR
	&& scalar(@ARGV) == 0
	&& defined($DEVICE)
    ) {
    printf STDERR "%s %s (perl %g)\n", $0, $VERSION, $];
    print STDERR "Usage: $0 [options...] arguments\n";
    print STDERR <<"EOF";
       --help                  output manpage and exit
       --debug                 enable debug mode
       --verbose               verbose status reporting
       --device=DEVICE         device SDcard is mounted on (ie, sdd) [REQUIRED]
       --slice=N               logical partition number 5..8         [optional]
       --boardrev=N            PCB board rev, 5 (default) or 6       [optional]
       --xmlfile=XMLFILE       generated .xml description file       [optional]
       --readfile=IMGFILE      image file to read from disk          [optional]
       --writefile=IMGFILE     image file to write to disk           [optional]
       --comparefile=IMGFILE   image file to compare to disk         [optional]
       --scsi=S1[,S2[,S3[,S4]]]       scsi id per partition          [optional]
       --partitions=P1[,P2[,P3[,P4]]] logical partition sizes        [optional]
EOF
    # exit if errors...
    die "Aborted due to command line errors.\n";
}

# ------------------------------------------------------------------------------

# database setup

my %db = ();
my %slice = ();
my $devfile = '/dev/'.$DEVICE;

my %disktab = ( # type    legacy#blocks      assigned#blocks      size-in-MB        text-description
		RL01 => { actual =>   10240, allocate =>   10240, capacity =>    5, description => 'DEC RL01' },
                RL02 => { actual =>   20480, allocate =>   20480, capacity =>   10, description => 'DEC RL02' },
                RD51 => { actual =>   21600, allocate =>   22528, capacity =>   11, description => 'DEC RD51 Winchester' },
                RK06 => { actual =>   27126, allocate =>   28672, capacity =>   14, description => 'DEC RK06' },
                RD31 => { actual =>   41560, allocate =>   43008, capacity =>   21, description => 'DEC RD31 Winchester' },
                RC25 => { actual =>   50902, allocate =>   51200, capacity =>   25, description => 'RCF25' },
                RK07 => { actual =>   53790, allocate =>   55296, capacity =>   27, description => 'DEC RK07' },
                RD52 => { actual =>   60480, allocate =>   61440, capacity =>   30, description => 'DEC RD52 Winchester' },
                RD32 => { actual =>   83236, allocate =>   83968, capacity =>   41, description => 'DEC RD32 Winchester' },
                RZ22 => { actual =>  102432, allocate =>  104448, capacity =>   51, description => 'DEC RZ22 Winchester' },
              AMP980 => { actual =>  131680, allocate =>  133120, capacity =>   65, description => 'AMPEX DM980' },
                RM03 => { actual =>  131680, allocate =>  133120, capacity =>   65, description => 'DEC RM03' },
                RD33 => { actual =>  138565, allocate =>  139264, capacity =>   68, description => 'DEC RD33 Winchester' },
                RD53 => { actual =>  138672, allocate =>  139264, capacity =>   68, description => 'DEC RD53 Winchester' },
                RP05 => { actual =>  171798, allocate =>  172032, capacity =>   84, description => 'DEC RP05' },
                RZ23 => { actual =>  204864, allocate =>  206848, capacity =>  101, description => 'DEC RZ23 Winchester' },
                RA80 => { actual =>  237212, allocate =>  237568, capacity =>  116, description => 'DEC RA80 Winchester' },
               RZ23L => { actual =>  237588, allocate =>  239616, capacity =>  117, description => 'DEC RZ23L Winchester' },
                RM80 => { actual =>  242606, allocate =>  243712, capacity =>  119, description => 'DEC RM80' },
                RB80 => { actual =>  242606, allocate =>  243712, capacity =>  119, description => 'DEC R80 on 730 IDC' },
               ESE20 => { actual =>  245757, allocate =>  245760, capacity =>  120, description => 'DEC ESE20 Electronic' },
             CDC9730 => { actual =>  263360, allocate =>  264192, capacity =>  129, description => 'CDC 9730' },
              FUJ160 => { actual =>  263360, allocate =>  264192, capacity =>  129, description => 'Fujitsu 160' },
                RF30 => { actual =>  293040, allocate =>  294912, capacity =>  144, description => 'DEC RF30 Winchester' },
                RD54 => { actual =>  311200, allocate =>  311296, capacity =>  152, description => 'DEC RD54 Winchester' },
                RP06 => { actual =>  340670, allocate =>  342016, capacity =>  167, description => 'DEC RP06' },
                RA60 => { actual =>  400176, allocate =>  401408, capacity =>  196, description => 'DEC RA60 Removable' },
                RZ24 => { actual =>  409792, allocate =>  411648, capacity =>  201, description => 'DEC RZ24 Winchester' },
             AMP9300 => { actual =>  495520, allocate =>  495616, capacity =>  242, description => 'Ampex 9300' },
             CDC9766 => { actual =>  500384, allocate =>  501760, capacity =>  245, description => 'CDC 9766' },
                RM05 => { actual =>  500384, allocate =>  501760, capacity =>  245, description => 'DEC RM05' },
              AMP330 => { actual =>  524288, allocate =>  524288, capacity =>  256, description => 'Ampex Capricorn' },
                RA70 => { actual =>  547041, allocate =>  548864, capacity =>  268, description => 'DEC RA70 Winchester' },
                RZ55 => { actual =>  649040, allocate =>  649216, capacity =>  317, description => 'DEC RZ55 Winchester' },
                RF31 => { actual =>  744400, allocate =>  745472, capacity =>  364, description => 'DEC RF31 Winchester' },
                RF71 => { actual =>  781440, allocate =>  782336, capacity =>  382, description => 'DEC RF71 Winchester' },
               EAGLE => { actual =>  808320, allocate =>  808960, capacity =>  395, description => 'Fujitsu Eagle (48 sectors)' },
                RZ25 => { actual =>  832527, allocate =>  833536, capacity =>  407, description => 'DEC RZ25 Winchester' },
                RA81 => { actual =>  891072, allocate =>  892928, capacity =>  436, description => 'DEC RA81 Winchester' },
                RP07 => { actual => 1008000, allocate => 1009664, capacity =>  493, description => 'DEC RP07' },
             CDC9775 => { actual => 1079040, allocate => 1079296, capacity =>  527, description => 'CDC 9775' },
                RA82 => { actual => 1216665, allocate => 1218560, capacity =>  595, description => 'DEC RA82 Winchester' },
                RZ56 => { actual => 1299174, allocate => 1300480, capacity =>  635, description => 'DEC RZ56 Winchester' },
                RZ80 => { actual => 1308930, allocate => 1310720, capacity =>  640, description => 'Maxtor 8760 Winchester' },
                RA71 => { actual => 1367310, allocate => 1368064, capacity =>  668, description => 'DEC RA71 Winchester' },
                RA72 => { actual => 1953300, allocate => 1953792, capacity =>  954, description => 'DEC RA72 Winchester' },
                RF72 => { actual => 1954050, allocate => 1955840, capacity =>  955, description => 'DEC RF72 Winchester' },
                RZ57 => { actual => 2025788, allocate => 2027520, capacity =>  990, description => 'DEC RZ57 Winchester' },
               M2266 => { actual => 2096256, allocate => 2097152, capacity => 1024, description => 'Fujitsu M2266' },
               M2694 => { actual => 2117025, allocate => 2117632, capacity => 1034, description => 'Fujitsu M2694' },
                RA90 => { actual => 2376153, allocate => 2377728, capacity => 1161, description => 'DEC RA90 Winchester' },
                RZ58 => { actual => 2698061, allocate => 2699264, capacity => 1318, description => 'DEC RZ58 Winchester' },
                RA92 => { actual => 2940951, allocate => 2942976, capacity => 1437, description => 'DEC RA92 Winchester' },
               M2652 => { actual => 3409965, allocate => 3411968, capacity => 1666, description => 'Fujitsu M2652' },
		RA73 => { actual => 3920490, allocate => 3921920, capacity => 1915, description => 'DEC RA73 Winchester' },
	     ST32171 => { actual => 4110000, allocate => 4110336, capacity => 2007, description => 'Seagate ST32171N' },
	     ST32550 => { actual => 4194995, allocate => 4196352, capacity => 2049, description => 'Seagate ST32550N' },
    );

# defaults
$db{ByteCount} = undef;
$db{SectorCount} = undef;
$db{SectorSize} = 512;
$db{IDcode} = 0xDA;

# ------------------------------------------------------------------------------

# initialize SDcard device structure

if (defined($DEVICE) && defined($PARTITIONS)) {

    # setup for expect
    my $prompt_cmd = qr/\nCommand \(m for help\): /;
    my $timeout = 10;

    # launch fdisk as an interactive subprocess
    my $exp = Expect->spawn('/sbin/fdisk', '--color=never', $devfile) or die;

    # enable debugging if set to 1
    $exp->exp_internal(0);

    # init MBR
    $exp->expect($timeout,
		 [ $prompt_cmd, sub { $exp->send("o\n"); } ] );

    # print disk info
    $exp->expect($timeout,
		 [ $prompt_cmd, sub { $exp->send("p\n"); exp_continue; } ],
		 [ qr/\nDisk \S+: \S+ \S+, (\d+) bytes, (\d+) sectors/,
		   sub { $db{ByteCount}   = ($exp->matchlist)[0];
			 $db{SectorCount} = ($exp->matchlist)[1];
			 $db{SectorSize}  = int($db{ByteCount}/$db{SectorCount}); } ] );

    # compute size of extra FAT partition as about 100MB; use rest for data partitions
    my $use_size_mb = int($db{ByteCount}/1048576 - 100.5);

    # create logical container partition 1
    $exp->expect($timeout,
		 [ $prompt_cmd,            sub { $exp->send("n\n"); exp_continue; } ],
		 [ qr/\nSelect.+: /,       sub { $exp->send("e\n"); exp_continue; } ],
		 [ qr/\nPartition.+: /,    sub { $exp->send("1\n"); exp_continue; } ],
		 [ qr/\nFirst sector.+: /, sub { $exp->send("\n");  exp_continue; } ],
		 [ qr/\nLast sector.+: /,  sub { $exp->send("+".$use_size_mb."M\n"); } ] );

    # create filesystem partition 2
    $exp->expect($timeout,
		 [ $prompt_cmd,            sub { $exp->send("n\n"); exp_continue; } ],
		 [ qr/\nSelect.+: /,       sub { $exp->send("p\n"); exp_continue; } ],
		 [ qr/\nPartition.+: /,    sub { $exp->send("2\n"); exp_continue; } ],
		 [ qr/\nFirst sector.+: /, sub { $exp->send("\n");  exp_continue; } ],
		 [ qr/\nLast sector.+: /,  sub { $exp->send("\n"); } ] );

    # change filesystem partition 2 to FAT32
    $exp->expect($timeout,
		 [ $prompt_cmd,            sub { $exp->send("t\n"); exp_continue; } ],
		 [ qr/\nPartition.+: /,    sub { $exp->send("2\n"); exp_continue; } ],
		 [ qr/\nHex code.+: /,     sub { $exp->send("0b\n"); } ] );

    # create data partitions
    foreach my $entry (split(/,/,uc($PARTITIONS))) {

	# partition size; lookup from table, else just use it
	my $size = exists $disktab{$entry} ? $disktab{$entry}{allocate}-1 : $entry;

	# created partition number
	my $n = undef;

	# create data partition N
	$exp->expect($timeout,
		     [ $prompt_cmd,            sub { $exp->send("n\n"); exp_continue; } ],
		     [ qr/\nSelect.+: /,       sub { $exp->send("l\n"); exp_continue; } ],
		     [ qr/\nAdding logical partition (\d+)/,
		                               sub { $n = ($exp->matchlist)[0]; exp_continue; } ],
		     [ qr/\nFirst sector.+: /, sub { $exp->send("\n");  exp_continue; } ],
		     [ qr/\nLast sector.+: /,  sub { $exp->send("+".$size."\n"); } ] );

	# change data partition N to raw data
	if (defined($n)) {
	    $exp->expect($timeout,
			 [ $prompt_cmd,         sub { $exp->send("t\n");   exp_continue; } ],
			 [ qr/\nPartition.+: /, sub { $exp->send($n."\n"); exp_continue; } ],
			 [ qr/\nHex code.+: /,  sub { $exp->send(sprintf("%02x\n",$db{IDcode})); } ] );
	}

	# exit loop if created last partition
	last if $n >= 8;
	
    } # foreach my $entry

    # print partitions
    $exp->expect($timeout,
		 [ $prompt_cmd, sub { $exp->send("p\n"); } ] );

    # write and quit
    $exp->expect($timeout,
		 [ $prompt_cmd, sub { $exp->send("w\n"); } ] );

    # and done
    $exp->soft_close();

}

# ------------------------------------------------------------------------------

# gather data from existing SDcard device

if (defined($DEVICE)) {

    # read the partition map and get the partitions of the selected type
    if (open(my $fh, '-|', '/sbin/fdisk --list '.$devfile)) {

	# scan all lines
	while (my $line = scalar(<$fh>)) {
	    $line =~ s/[\015\012]+$//;
	    if ($line =~ m/^${devfile}(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\S+)\s+(\S+)/i) {
		# process partition definition lines
		my ($id, $start, $end, $count, $size, $type) = ($1+0,$2+0,$3+0,$4+0,$5,hex($6));
		if ($type == $db{IDcode} && $count == $end-$start+1) {
		    $slice{$id}{start} = $start;
		    $slice{$id}{end}   = $end;
		    $slice{$id}{count} = $count;
		}
	    } elsif ($line =~ m/^disk\s+${devfile}:\s+[0-9.]+\s+[a-z]+,\s+(\d+)\s+bytes,\s+(\d+)\s+sectors/i) {
		# process line with total physical device byte and sector count
		$db{ByteCount} = ($1+0);
		$db{SectorCount} = ($2+0);
		$db{SectorSize} = int($db{ByteCount}/$db{SectorCount});
	    }
	}

	close($fh);

    } # if (open(my $fh ...

    if ($DEBUG) {
	printf STDERR "\n[ SectorSize  = %d ]\n", $db{SectorSize};
	printf STDERR "[ SectorCount = %d ]\n", $db{SectorCount};
	printf STDERR "[ ByteCount   = %d ]\n\n", $db{ByteCount};
	printf STDERR "[ Device         Sector     Sector     Sector ]\n";
	printf STDERR "[    & Slice      Start        End      Count ]\n";
	foreach my $id (sort(keys(%slice))) {
	    printf STDERR "[ %-10s %10d %10d %10d ]\n", $devfile.$id,
	                  $slice{$id}{start}, $slice{$id}{end}, $slice{$id}{count};
	}
	printf STDERR "\n";
    }

}

# ------------------------------------------------------------------------------

# write image file to partition

if (defined($DEVICE) && defined($WRITEFILE) && defined($SLICE)) {

    # some parameters
    my $blksize = $db{SectorSize};
    my $bufsize = 2048*$blksize;

    # configure partition start/length blocks
    my $start = $slice{$SLICE}{start};
    my $end   = $slice{$SLICE}{end};
    my $count = $slice{$SLICE}{count};

    # check input exists
    if (open(my $ifh, '<', $WRITEFILE)) {
	# check output exists
	if (open(my $ofh, '+<', $devfile)) {
	    # seek to output position
	    die unless sysseek($ofh, $start*$blksize, 0) == $start*$blksize;
	    # this many bytes per chunk
	    my $buffer = undef;
	    # read/write byte counts
	    my $rdtotal = 0;
	    my $wrtotal = 0;
	    # read/write byte positions
	    my $rdpos = sysseek($ifh, 0, 1);
	    my $wrpos = sysseek($ofh, 0, 1);
	    while ((my $rdsize = sysread($ifh, $buffer, $bufsize)) > 0) {
		# read bytes
		$rdtotal += $rdsize;
		printf STDERR "[ write slice %d rd %12d at %12d ]\n", $SLICE, $rdsize, $rdpos if $DEBUG;
		# check write bytes vs partition size; set partition size as maximum
		if ($wrtotal+$rdsize > $count*$blksize) {
		    $rdsize = $count*$blksize - $wrtotal;
		    printf STDERR "Write overflow; truncating read to %d bytes\n", $rdsize;
		}
		# write bytes
		my $wrsize = syswrite($ofh, $buffer, $rdsize);
		$wrtotal += $wrsize;
		printf STDERR "[ write slice %d wr %12d at %12d ]\n", $SLICE, $wrsize, $wrpos if $DEBUG;
		# continue
		$rdpos = sysseek($ifh, 0, 1);
		$wrpos = sysseek($ofh, 0, 1);
	    } # while ((my $rdsize ...
	    # summary
	    printf STDERR "Write image file %s %d bytes to slice %d %d bytes\n",
	                  $WRITEFILE, $rdtotal, $SLICE, $wrtotal if $VERBOSE;
	    close($ofh);
	} # if (open(my $ofh ...
	close($ifh);
    } # if (open(my $ifh ...

}

# ------------------------------------------------------------------------------

# read partition to image file

if (defined($DEVICE) && defined($READFILE) && defined($SLICE)) {

    # some parameters
    my $blksize = $db{SectorSize};
    my $bufsize = 2048*$blksize;

    # configure partition start/length blocks
    my $start = $slice{$SLICE}{start};
    my $end   = $slice{$SLICE}{end};
    my $count = $slice{$SLICE}{count};

    # check input exists
    if (open(my $ifh, '+<', $devfile)) {
	# create output file
	if (open(my $ofh, '>', $READFILE)) {
	    # seek to input position
	    die unless sysseek($ifh, $start*$blksize, 0) == $start*$blksize;
	    # this many bytes per chunk
	    my $buffer = undef;
	    # read/write byte counts
	    my $rdtotal = 0;
	    my $wrtotal = 0;
	    # read/write byte positions
	    my $rdpos = sysseek($ifh, 0, 1);
	    my $wrpos = sysseek($ofh, 0, 1);
	    while ($rdtotal < $count*$blksize) {
		# shrink buffer on last read if extends past partition
		$bufsize = $count*$blksize - $rdtotal if $rdtotal+$bufsize > $count*$blksize;
		# read bytes
		my $rdsize = sysread($ifh, $buffer, $bufsize);
		$rdtotal += $rdsize;
		printf STDERR "[ read slice %d rd %12d at %12d ]\n", $SLICE, $rdsize, $rdpos if $DEBUG;
		# write bytes
		my $wrsize = syswrite($ofh, $buffer, $rdsize);
		$wrtotal += $wrsize;
		printf STDERR "[ read slice %d wr %12d at %12d ]\n", $SLICE, $wrsize, $wrpos if $DEBUG;
		# continue
		$rdpos = sysseek($ifh, 0, 1);
		$wrpos = sysseek($ofh, 0, 1);
	    } # while ((my $rdsize ...
	    # summary
	    printf STDERR "Read slice %d %d bytes to image file %s %d bytes\n",
	                  $SLICE, $rdtotal, $READFILE, $wrtotal if $VERBOSE;
	    close($ofh);
	} # if (open(my $ofh ...
	close($ifh);
    } # if (open(my $ifh ...

}

# ------------------------------------------------------------------------------

# read partition to temp file and compare to named file

if (defined($DEVICE) && defined($COMPAREFILE) && defined($SLICE)) {

    # some parameters
    my $blksize = $db{SectorSize};
    my $bufsize = 2048*$blksize;

    # configure partition start/length blocks
    my $start = $slice{$SLICE}{start};
    my $end   = $slice{$SLICE}{end};
    my $count = $slice{$SLICE}{count};

    # locals
    my $tmpfile = sprintf("img2sdcard_%s%d_%d.tmp", $DEVICE, $SLICE, $$);

    # check input exists
    if (open(my $ifh, '+<', $devfile)) {
	# create output file
	if (open(my $ofh, '>', $tmpfile)) {
	    # seek to input position
	    die unless sysseek($ifh, $start*$blksize, 0) == $start*$blksize;
	    # this many bytes per chunk
	    my $buffer = undef;
	    # read/write byte counts
	    my $rdtotal = 0;
	    my $wrtotal = 0;
	    # read/write byte positions
	    my $rdpos = sysseek($ifh, 0, 1);
	    my $wrpos = sysseek($ofh, 0, 1);
	    while ($rdtotal < $count*$blksize) {
		# shrink buffer on last read if extends past partition
		$bufsize = $count*$blksize - $rdtotal if $rdtotal+$bufsize > $count*$blksize;
		# read bytes
		my $rdsize = sysread($ifh, $buffer, $bufsize);
		$rdtotal += $rdsize;
		printf STDERR "[ read slice %d rd %12d at %12d ]\n", $SLICE, $rdsize, $rdpos if $DEBUG;
		# write bytes
		my $wrsize = syswrite($ofh, $buffer, $rdsize);
		$wrtotal += $wrsize;
		printf STDERR "[ read slice %d wr %12d at %12d ]\n", $SLICE, $wrsize, $wrpos if $DEBUG;
		# continue
		$rdpos = sysseek($ifh, 0, 1);
		$wrpos = sysseek($ofh, 0, 1);
	    } # while ((my $rdsize ...
	    close($ofh);
	} # if (open(my $ofh ...
	close($ifh);
    } # if (open(my $ifh ...

    # now do the compare
    if (-r $tmpfile && -r $COMPAREFILE) {
	# compare only length of compare file
	my $len = (stat($COMPAREFILE))[7];
	# do the compare, print result
	my $sts = system('/usr/bin/cmp', '-b', '-n '.$len, $tmpfile, $COMPAREFILE);
        printf STDERR "Compare slice %d %d bytes to image file %s %d bytes; status is '%s'\n",
	              $SLICE, $len, $COMPAREFILE, $len, $sts == 0 ? 'files match' : 'FILES DIFFER';
	# delete tmp file if no error and not debug
	unlink($tmpfile) if -e $tmpfile && $sts == 0 && !$DEBUG;
    }

}

# ------------------------------------------------------------------------------

# write an XML description file if requested and device exists

if (defined($DEVICE) && defined($XMLFILE)) {

    my $header = 'SCSI2SD';
    my $config = ($BOARDREV <= 5) ? 'BoardConfig' : 'S2S_BoardCfg';
    my $target = 'SCSITarget';
    my $units  = ($BOARDREV <= 5) ? 4 : 6;

    if (open(my $fh, '>', $XMLFILE)) {

	# BoardConfig
	my %bc = (
	    # rev 5 or less
	    disableGlitchFilter => { rev => 5, value => 'false' },
	    enableCache         => { rev => 5, value => 'false' },
	    enableDisconnect    => { rev => 5, value => 'true' },
	    # any rev but variable default
	    enableScsi2         => { rev => 0, value => ($BOARDREV <= 5 ? 'false' : 'true') },
	    enableTerminator    => { rev => 0, value => ($BOARDREV <= 5 ? 'false' : 'true') },
	    # any rev
	    mapLunsToIds        => { rev => 0, value => 'false' },
	    parity              => { rev => 0, value => 'true' },
	    scsiSpeed           => { rev => 0, value => '0' },
	    selLatch            => { rev => 0, value => 'false' },
	    selectionDelay      => { rev => 0, value => '255' },
	    startupDelay        => { rev => 0, value => '0' },
	    unitAttention       => { rev => 0, value => 'true' },
	    );

	# SCSITarget per unit
	my %st = (
	    # any rev
	    enabled            => { rev => 0, value => 'false' }, # overwritten
	    deviceType         => { rev => 0, value => '0x0' },
	    deviceTypeModifier => { rev => 0, value => '0x0' },
	    #
	    bytesPerSector     => { rev => 0, value => '512' },
	    headsPerCylinder   => { rev => 0, value => '255' },
	    sectorsPerTrack    => { rev => 0, value => '63' },
	    #
	    sdSectorStart      => { rev => 0, value => sprintf("%d",0) }, # overwritten
	    scsiSectors        => { rev => 0, value => sprintf("%d",100000) }, # overwritten
	    #
	    vendor             => { rev => 0, value => 'SCSItoSD' },
	    prodId             => { rev => 0, value => sprintf("%-16s",'RA81') }, # overwritten
	    revision           => { rev => 0, value => '0001' },
	    serial             => { rev => 0, value => sprintf("%-16d",12345) }, # overwritten
	    quirks             => { rev => 0, value => '' },
	    # rev 5 or less
	    modePages          => { rev => 5, value => '' },
	    vpd                => { rev => 5, value => '' },
	    );

	# XML header
	printf $fh "<%s>\n", $header;

	# board configuration
	printf $fh "    <%s>\n", $config;
	foreach my $key (sort(keys(%bc))) {
	    printf $fh "        <%s>%s</%s>\n", $key, $bc{$key}{value}, $key
		if $bc{$key}{rev} == 0 || $bc{$key}{rev} == $BOARDREV;
	}
	printf $fh "    </%s>\n", $config;

	# list of defined units and corresponding scsi id
	my @list = sort({$a <=> $b}keys(%slice));
	my @scsi = defined($SCSI) ? (split(/,/,$SCSI)) : (0..$#list);

	# mapped units in SCSItoSD
	for (my $unit = 0; $unit < $units; $unit++) {
	    # get unit number from list
	    my $id = $list[$unit];
	    # (assume) unit is undefined/disabled
	    $st{enabled}{value} = 'false';
	    # configure partition start/length
	    $st{sdSectorStart}{value} = sprintf("%d", 4096);
	    $st{scsiSectors}{value} = sprintf("%d", 4096);
	    # fake device type
	    $st{prodId}{value} = sprintf("%-16s", '*DISABLED*');
	    # unique serial always
	    $st{serial}{value} = sprintf("%-16d", 1000+$unit);
	    # check if less than all units defined
	    if (defined($id)) {
		# unit is defined/enabled
		$st{enabled}{value} = 'true';
		# configure partition start/length
		$st{sdSectorStart}{value} = sprintf("%d", $slice{$id}{start});
		$st{scsiSectors}{value} = sprintf("%d", $slice{$id}{count});
		# search type database for next same or larger entry
		my @types = sort({$disktab{$a}{allocate}<=>$disktab{$b}{allocate}}keys(%disktab));
		foreach my $type (@types) {
		    $st{prodId}{value} = sprintf("%-16s", $type);
		    last if $disktab{$type}{allocate} >= $slice{$id}{count};
		}
	    }
	    # get allocated scsi ID, else find an unused one
	    my $scsiID = $scsi[$unit];
	    # if it exists, use it
	    if (!defined($scsiID)) {
		# else find next unused scsi ID
		foreach my $try (0..7) {
		    # search all allocated IDs, find next non-match
		    if (grep($try == $_, @scsi) == 0) {
			# found an unused ID, allocate it
			$scsiID = $try;
			$scsi[$unit] = $scsiID;
			# and we are done
			last;
		    }
		}
		# can't ever get here as there are =8 scsiIDs and <8 slots
	    }
	    # print per unit configuration
	    printf $fh "    <%s id=\"%d\">\n", $target, $scsiID;
	    foreach my $key (sort(keys(%st))) {
		printf $fh "        <%s>%s</%s>\n", $key, $st{$key}{value}, $key
		    if $st{$key}{rev} == 0 || $st{$key}{rev} == $BOARDREV;
	    }
	    printf $fh "    </%s>\n", $target;
	} # foreach my $unit ...

	# XML trailer
	printf $fh "</%s>\n", $header;

	# all done
	close($fh);
    } # if (open(my $fh ...

}

# ------------------------------------------------------------------------------

exit;

# ------------------------------------------------------------------------------

# the end
