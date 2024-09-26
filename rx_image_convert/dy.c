#include <stdio.h>

#define DY_TRACKS      77
#define DY_SECTORS     26
#define DY_NUM_BLOCKS  ((DY_TRACKS-1) * DY_SECTORS)


int lbn2dy (int lbn)
{
	int track;
	int sector;
	int half;

	track    = lbn / DY_SECTORS;

	/* interleave 2 */
	sector   = lbn % DY_SECTORS;
	half     = sector >= DY_SECTORS / 2 ? 1 : 0;
	sector <<= 1;
	sector  |= half;

        /* track skew of 6 */
	sector  += track << 1;
	sector  += track << 1;
	sector  += track << 1;

	sector %= DY_SECTORS;
	track++;
	track  %= DY_TRACKS;

	return track * DY_SECTORS + sector;
}

int main()
{
    int n, m, t, s;
    for (n = 0;  n < DY_NUM_BLOCKS;  ++n) {
        m = lbn2dy(n);
        t = m / DY_SECTORS;
        s = 1 + (m % DY_SECTORS);
        printf("Log Blk %4d -> Phy Trk %2d Sec %2d\n", n, t, s);
        if (n % DY_SECTORS == DY_SECTORS-1) printf("\n");
    }
}
