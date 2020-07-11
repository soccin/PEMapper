#!/bin/bash
SDIR="$( cd "$( dirname "$0" )" && pwd )"
export PATH=$SDIR/bin:$PATH

BAM=$1

mkdir -p cache

if [ -e ${BAM/.bam/_FixHdr.bai} ]; then
    echo "Moving" $BAM
    mv $BAM ${BAM/.bam/.bai} cache
else
    echo "FixHdr.bai does not exist, do not delete"
    echo "Rerun fixHeader" $BAM
fi

