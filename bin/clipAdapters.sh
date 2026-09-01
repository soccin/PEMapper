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

##
# The exit status of this script is the status slurm records for the job
# and the status bin/checkRun.sh reports. Both branches used to end on a
# command that always succeeds -- `deactivate` and a bare `wait` -- so a
# cutadapt failure produced an empty CLIP fastq and a COMPLETED job.

if [ "$NO_CLIP" == "Yes" ]; then

    zcat $FASTQ1 >${BASE1}___CLIP.fastq &
    ZCATPID=$!

    zcat $FASTQ2 >${BASE2}___CLIP.fastq
    RC2=$?

    wait $ZCATPID
    RC1=$?

    if [ "$RC1" != "0" ] || [ "$RC2" != "0" ]; then
        echo "FATAL ERROR [$SNAME]: zcat failed, R1 rc=[$RC1] R2 rc=[$RC2]"
        exit 1
    fi

else

    . $SDIR/venv/bin/activate

    cutadapt -O 10 -q 3 -m $MINLENGTH -e $ERROR \
        -a $ADAPTER -A $ADAPTER \
        -o ${BASE1}___CLIP.fastq -p ${BASE2}___CLIP.fastq \
        $FASTQ1 $FASTQ2
    RC=$?

    deactivate

    if [ "$RC" != "0" ]; then
        echo "FATAL ERROR [$SNAME]: cutadapt failed rc=[$RC]"
        exit $RC
    fi

fi
