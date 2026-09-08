#!/bin/bash

#
# Submit with the system sbatch. pipe.sh puts $SDIR/bin at the front of
# PATH and there may also be a personal ~/bin/sbatch wrapper, so go
# straight to the real binary the way bin/bsub.sh used to.
#

exec /usr/bin/sbatch "$@"
