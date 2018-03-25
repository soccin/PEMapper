#!/bin/bash

SNAME=$(basename $0)
SDIR="$( cd "$( dirname "$0" )" && pwd )"

# -e .2 (20%) error
# For len 13 adapter (Maximal HiSeq Default)
# No. of allowed errors:
# 0-4 bp: 0; 5-9 bp: 1; 10-13 bp: 2

numBlocks=$1
block=$2

ODIR=$SCRATCH/scatterFASTQ/$block
mkdir -p $ODIR

ADAPTER=$3
FASTQ1=$4
FASTQ2=$5
BASE1=$ODIR/$(echo $FASTQ1 | tr '/' '_')
BASE2=$ODIR/$(echo $FASTQ2 | tr '/' '_')

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

TMPDIR=/scratch/$USER/scatterFASTQ/$block/$(uuidgen)
mkdir -p $TMPDIR

$SDIR/scatterFASTQ $numBlocks $block $FASTQ1 >$TMPDIR/tmp1_$$_.fastq &
$SDIR/scatterFASTQ $numBlocks $block $FASTQ2 >$TMPDIR/tmp2_$$_.fastq
wait

FASTQ1=$TMPDIR/tmp1_$$_.fastq
FASTQ2=$TMPDIR/tmp2_$$_.fastq

cutadapt -O 10 -q 3 -m $MINLENGTH -e $ERROR \
    -a $ADAPTER -A $ADAPTER \
    -o ${BASE1}___CLIP_${block}.fastq -p ${BASE2}___CLIP_${block}.fastq \
    $FASTQ1 $FASTQ2

sleep 15
rm -rf $TMPDIR
