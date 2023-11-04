#!/bin/bash

set -e

#
# picardV2 MarkDuplicates USE_JDK_INFLATER=TRUE USE_JDK_DEFLATER=TRUE MAX_RECORDS_IN_RAM=5000000 \
#   I=$OUTDIR/${SAMPLENAME}.bam \
#   O=$OUTDIR/${SAMPLENAME}___MD.bam \
#   M=$OUTDIR/${SAMPLENAME}___MD.txt \
#   CREATE_INDEX=true \
#   R=$GENOME_FASTA
#

function uuid_short {
    uuidgen | md5sum - | perl -ne 's/^(........)/\1/;print $1'
}

function on_exit {
    rm -rf $TDIR
}

INPUT=$1
GENOME_FASTA=$2

OUTPUT=${INPUT/.bam/___MD.bam}
METRICS=${INPUT/.bam/___MD.txt}
LOG=${INPUT/.bam/___MD.bam}.log

if [ -e /fscratch ]; then
    TDIR=/fscratch/socci/PEMapper/$(uuid_short)
else
    TDIR=/scratch/socci/PEMapper/$(uuid_short)
fi

echo TDIR=$TDIR | tee $LOG
mkdir -vp $TDIR | tee -a $LOG

trap on_exit EXIT

picard.local MarkDuplicates USE_JDK_INFLATER=TRUE USE_JDK_DEFLATER=TRUE MAX_RECORDS_IN_RAM=5000000 \
    I=$INPUT \
    O=$TDIR/$(basename $OUTPUT) \
    M=$TDIR/$(basename $METRICS) \
    CREATE_INDEX=true \
    R=$GENOME_FASTA

md5sum $TDIR/$(basename $OUTPUT) | tee -a $LOG
rsync -a $TDIR/* $(dirname $OUTPUT) | tee -a $LOG
sleep 60
rsync -avP $TDIR/* $(dirname $OUTPUT) | tee -a $LOG
md5sum $OUTPUT | tee -a $LOG


