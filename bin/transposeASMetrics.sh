#!/bin/bash

SDIR="$( cd "$( dirname "$0" )" && pwd )"

#
# stdout is the product: pipe.sh redirects this script into
# <SAMPLE>___ASt.txt, so anything else written here lands in the metrics
# file. This echo used to put an SDIR= line at the top of every one.
#
echo SDIR=$SDIR >&2

if [ ! -s "$1" ]; then
    echo "FATAL ERROR: missing or empty alignment summary metrics [$1]" >&2
    exit 1
fi

#
# Without pipefail the status is transpose.py's alone, so a failure
# reading the input still exits 0 and slurm records the job COMPLETED.
#
set -o pipefail

egrep -w "(CATEGORY|PAIR)" "$1" | $SDIR/transpose.py
