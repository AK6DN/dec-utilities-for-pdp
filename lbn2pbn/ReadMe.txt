I used the technique you outlined in one of your early messages on thisthread. The only difference was that I used RT-11 rather than RSX:

   - Boot RT-11 in simh (make sure RX is disabled and RY is enabled)

   - Copy the logical disk image to RT-11 (say as dl0:disk.log)

   - Attach a file to RY0:

     ^E
     simh> attach ry0 disk.phy
     simh> c

   - Use DUP to copy the image to the RX02

     .R DUP
     *DY0:*=DL0:DISK.LOG/I/F
     *^C

   - Detach the file from RY0

The file “disk.phy” is now a physical copy of the original disk with track 0 present and the data
correctly interleaved and skewed. I’ve been able to successfully boot the “AUTO”image mentioned above.
