# Getting started
Now this is a minimal setup of running a firecracker daemon for ci job.

You will see there are 5 directories
- bin/
- rootfs/
- runner/
- utils/
- script/


### bin
The bin contains a script ```download.sh``` which downloads the latest firecracker binary

### rootfs
In rootfs is where mounting is done 

### runner
```runner/``` contains

- ci.sh: This script is responsible for executing commands to firecracker
- 
