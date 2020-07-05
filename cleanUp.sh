#!/bin/bash
SDIR="$( cd "$( dirname "$0" )" && pwd )"
export PATH=$SDIR/bin:$PATH

BAM=$1

mkdir -p cache

mv $BAM ${BAM/.bam/.bai} cache

