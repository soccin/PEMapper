#!/bin/bash

SNAME=$(basename $0)
SDIR="$( cd "$( dirname "$0" )" && pwd )"

# -e .2 (20%) error
# For len 13 adapter (Maximal HiSeq Default)
# No. of allowed errors:
# 0-4 bp: 0; 5-9 bp: 1; 10-13 bp: 2

ADAPTER=$1
FASTQ1=$2
FASTQ2=$3
BASE1=$SCRATCH/$(echo $FASTQ1 | tr '/' '_')
BASE2=$SCRATCH/$(echo $FASTQ2 | tr '/' '_')

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
# zcat $FASTQ1 | head -40000 >$SCRATCH/tmp1_$$_.fastq
# zcat $FASTQ2 | head -40000 >$SCRATCH/tmp2_$$_.fastq
# FASTQ1=$SCRATCH/tmp1_$$_.fastq
# FASTQ2=$SCRATCH/tmp2_$$_.fastq


if [ "$NO_CLIP" == "Yes" ]; then

    zcat $FASTQ1 >${BASE1}___CLIP.fastq &
    zcat $FASTQ2 >${BASE2}___CLIP.fastq

    wait

else

    . $SDIR/venv/bin/activate

    cutadapt -O 10 -q 3 -m $MINLENGTH -e $ERROR \
        -a $ADAPTER -A $ADAPTER \
        -o ${BASE1}___CLIP.fastq -p ${BASE2}___CLIP.fastq \
        $FASTQ1 $FASTQ2

    deactivate

fi