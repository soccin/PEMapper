#!/bin/bash
SDIR="$( cd "$( dirname "$0" )" && pwd )"
export PATH=$SDIR/bin:$PATH

BAM=$1

rm $BAM ${BAM/.bam/.bai}

