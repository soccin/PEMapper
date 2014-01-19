#!/bin/bash

# -e .2 (20%) error
# For len 13 adapter (Maximal HiSeq Default)
# No. of allowed errors:
# 0-4 bp: 0; 5-9 bp: 1; 10-13 bp: 2


ADAPTER=$1
FASTQ1=$2
FASTQ2=$3
BASE1=$SCRATCH/$(basename $FASTQ1)
BASE2=$SCRATCH/$(basename $FASTQ2)

if [ "$MINLENGTH" == "" ]; then
    MINLENGTH=35
    echo Default MINLENGTH=$MINLENGTH set
fi

if [ "$ERROR" == "" ]; then
    ERROR=0.2
    echo Default ERROR=$ERROR set
fi

##
# Debug limit
gzcat $FASTQ1 | head -40000 >$SCRATCH/tmp1.fastq
gzcat $FASTQ2 | head -40000 >$SCRATCH/tmp2.fastq
FASTQ1=$SCRATCH/tmp1.fastq
FASTQ2=$SCRATCH/tmp2.fastq

cutadapt -m $MINLENGTH -a $ADAPTER -e $ERROR \
    --paired-output ${BASE2}.tmp.fastq -o ${BASE1}.tmp.fastq $FASTQ1 $FASTQ2 \
    > ${BASE1}.log

cutadapt -m $MINLENGTH -a $ADAPTER -e $ERROR \
    --paired-output ${BASE1}___CLIP.fastq -o ${BASE2}___CLIP.fastq ${BASE2}.tmp.fastq ${BASE1}.tmp.fastq \
    > ${BASE2}.log

