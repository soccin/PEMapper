#!/bin/bash

# -e .2 (20%) error
# For len 13 adapter (Maximal HiSeq Default)
# No. of allowed errors:
# 0-4 bp: 0; 5-9 bp: 1; 10-13 bp: 2


ADAPTER=$1
FASTQ=$2

echo $SCRATCH

#cutadapt -a $ADAPTER -e .2