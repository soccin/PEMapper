#!/bin/bash

set -e

#
# picard.local MergeSamFiles \
#     MAX_RECORDS_IN_RAM=5000000 SO=coordinate CREATE_INDEX=true \
#     O=$OUTDIR/${SAMPLENAME}.bam $INPUTS
#

function uuid_short {
    uuidgen | md5sum - | perl -ne 's/^(........)/\1/;print $1'
}

function on_exit {
    rm -rf $TDIR
}

OUTPUT=$1
shift 1

LOG=${OUTPUT}.log

if [ -e /fscratch ]; then
    TDIR=/fscratch/socci/PEMapper/$(uuid_short)
else
    TDIR=/scratch/socci/PEMapper/$(uuid_short)
fi

mkdir -p $(dirname $OUTPUT)

echo TDIR=$TDIR | tee $LOG
mkdir -vp $TDIR | tee -a $LOG

trap on_exit EXIT

picard.local MergeSamFiles \
     MAX_RECORDS_IN_RAM=5000000 SO=coordinate CREATE_INDEX=true \
     O=$TDIR/$(basename $OUTPUT) $@ | tee -a $LOG

md5sum $TDIR/$(basename $OUTPUT) | tee -a $LOG
rsync -a $TDIR/*.ba? $(dirname $OUTPUT) | tee -a $LOG
sleep 60
rsync -avP $TDIR/*.ba? $(dirname $OUTPUT) | tee -a $LOG
md5sum $OUTPUT | tee -a $LOG


