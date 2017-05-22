#!/bin/bash

SNAME=$(basename $0)

# -e .2 (20%) error
# For len 13 adapter (Maximal HiSeq Default)
# No. of allowed errors:
# 0-4 bp: 0; 5-9 bp: 1; 10-13 bp: 2

ADAPTER=$1
FASTQ1=$2
FASTQ2=$3
BASE1=$SCRATCH/$(echo $FASTQ1 | tr '/' '_')
BASE2=$SCRATCH/$(echo $FASTQ2 | tr '/' '_')

FASTX=/opt/common/CentOS_6/fastx_toolkit/fastx_toolkit-0.0.13

if [ "$MINLENGTH" == "" ]; then
    MINLENGTH=35
    echo $SNAME Default MINLENGTH=$MINLENGTH set
else
    echo $SNAME Explicit MINLENGTH=$MINLENGTH set
fi

if [ "$ERROR" == "" ]; then
    ERROR=0.1
    echo $SNAME Default ERROR=$ERROR set
fi

if [ "$TRIM_READS" != "" ]; then
    echo $SNAME "TRIM_READS =["$TRIM_READS"]"
    TAG=$(uuidgen)
    gzcat $FASTQ1 | $FASTX/fastx_trimmer -Q 33 -l $TRIM_READS -z >$SCRATCH/trim1_${TAG}_.fastq.gz
    gzcat $FASTQ2 | $FASTX/fastx_trimmer -Q 33 -l $TRIM_READS -z >$SCRATCH/trim2_${TAG}_.fastq.gz
    FASTQ1=$SCRATCH/trim1_${TAG}_.fastq.gz
    FASTQ2=$SCRATCH/trim2_${TAG}_.fastq.gz
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
    -a $ADAPTER -A $ADAPTER \
    -o ${BASE1}___CLIP.fastq -p ${BASE2}___CLIP.fastq \
    $FASTQ1 $FASTQ2
