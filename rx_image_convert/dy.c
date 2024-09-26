#include <stdio.h>

#define DY_TRACKS      77
#define DY_SECTORS     26
#define DY_NUM_BLOCKS  (DY_TRACKS * DY_SECTORS)


int lbn2dy(int lbn)
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
    int n, m;
    for (n = 0;  n < DY_NUM_BLOCKS;  ++n) {
        m = lbn2dy(n);
        printf("%d: %d %d -> %d: %d %d\n", n, n / DY_SECTORS, n % DY_SECTORS, m, m / DY_SECTORS, m % DY_SECTORS);
    }
}
