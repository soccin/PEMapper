#!/bin/bash

SNAME=$(basename $0)

# -e .2 (20%) error
# For len 13 adapter (Maximal HiSeq Default)
# No. of allowed errors:
# 0-4 bp: 0; 5-9 bp: 1; 10-13 bp: 2

ADAPTER=$1
FASTQ1=$2
BASE1=$SCRATCH/$(echo $FASTQ1 | tr '/' '_')

if [ "$MINLENGTH" == "" ]; then
    MINLENGTH=35
    echo $SNAME Default MINLENGTH=$MINLENGTH set
fi

if [ "$ERROR" == "" ]; then
    ERROR=0.1
    echo $SNAME Default ERROR=$ERROR set
fi

##
# Debug limit
# Added $$ to name so no collisions with multiple jobs
#
# gzcat $FASTQ1 | head -40000 >$SCRATCH/tmp1_$$_.fastq
# gzcat $FASTQ2 | head -40000 >$SCRATCH/tmp2_$$_.fastq
# FASTQ1=$SCRATCH/tmp1_$$_.fastq
# FASTQ2=$SCRATCH/tmp2_$$_.fastq

cutadapt -O 10 -q 3 -m $MINLENGTH -e $ERROR \
    -a $ADAPTER \
    -o ${BASE1}___CLIP.fastq \
    $FASTQ1 
