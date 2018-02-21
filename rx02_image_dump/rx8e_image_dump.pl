#!/usr/bin/perl -w

foreach my $file (@ARGV) {

    if (open(INP, "< $file")) {
	my $size = (stat($file))[7];
	die unless $size == 76*26*128 || $size == 77*26*128;
	my ($sector,$track,$byte) = (1,0,undef);
	$track++ if $size == 76*26*128;
	while (!eof(INP)) {
	    my $sts = read(INP,$byte,128);
	    my @byte = unpack('C128',$byte);
	    my @rest = splice(@byte,-32,32);
	    my @word = map {0xFFF&((($byte[3*($_>>1)+2]<<16)|($byte[3*($_>>1)+1]<<8)|($byte[3*($_>>1)+0]))>>(($_%2)*12))} (0..63);
	    printf "\n%3d %2d ", $track, $sector;
	    printf "%1s%s => %s\n", '', join(' ',map {sprintf("%02X",$_)} @byte[0..11]),  join(' ',map {sprintf("%04o",$_)} @word[0..7]);
	    printf "%8s%s => %s\n", '', join(' ',map {sprintf("%02X",$_)} @byte[12..23]), join(' ',map {sprintf("%04o",$_)} @word[8..15]);
	    printf "%8s%s => %s\n", '', join(' ',map {sprintf("%02X",$_)} @byte[24..35]), join(' ',map {sprintf("%04o",$_)} @word[16..23]);
	    printf "%8s%s => %s\n", '', join(' ',map {sprintf("%02X",$_)} @byte[36..47]), join(' ',map {sprintf("%04o",$_)} @word[24..31]);
	    printf "%8s%s => %s\n", '', join(' ',map {sprintf("%02X",$_)} @byte[48..59]), join(' ',map {sprintf("%04o",$_)} @word[32..39]);
	    printf "%8s%s => %s\n", '', join(' ',map {sprintf("%02X",$_)} @byte[60..71]), join(' ',map {sprintf("%04o",$_)} @word[40..47]);
	    printf "%8s%s => %s\n", '', join(' ',map {sprintf("%02X",$_)} @byte[72..83]), join(' ',map {sprintf("%04o",$_)} @word[48..55]);
	    printf "%8s%s => %s\n", '', join(' ',map {sprintf("%02X",$_)} @byte[84..95]), join(' ',map {sprintf("%04o",$_)} @word[56..63]);
	    if (0) {
		printf "%7s[%s]\n", '', join(' ',map {sprintf("%02X",$_)} @rest[0..15]);
		printf "%7s[%s]\n", '', join(' ',map {sprintf("%02X",$_)} @rest[16..31]);
	    }
	    $track++ if $sector==26;
	    $sector = $sector==26 ? 1 : $sector+1;
	}
    }
    close(INP);

}

# the end
