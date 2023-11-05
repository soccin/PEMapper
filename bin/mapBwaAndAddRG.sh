#!/bin/bash

set -e

# echo -e "@PG\tID:$PIPENAME\tVN:$SCRIPT_VERSION\tCL:$0 ${COMMAND_LINE}" > $SCRATCH/${BASE1%%.fastq*}.version.txt
#
# QRUN $BWA_THREADS ${TAG}_MAP_02__$UUID HOLD ${TAG}_MAP_01__$UUID VMEM 32 \
#     bwa mem $BWA_OPTS -t $BWA_THREADS $GENOME_BWA $CLIPSEQ1 $CLIPSEQ2 \>\>$SCRATCH/${BASE1%%.fastq*}.sam
#
# QRUN 2 ${TAG}_MAP_03__$UUID HOLD ${TAG}_MAP_02__$UUID VMEM 26 \
#     picard.local AddOrReplaceReadGroups MAX_RECORDS_IN_RAM=5000000 CREATE_INDEX=true SO=coordinate \
#     LB=$SAMPLENAME PU=${BASE1%%_R1_*} SM=$SAMPLENAME PL=illumina CN=GCL \
#     I=$SCRATCH/${BASE1%%.fastq*}.sam O=$SCRATCH/${BASE1%%.fastq*}.bam
#

function uuid_short {
    uuidgen | md5sum - | perl -ne 's/^(........)/\1/;print $1'
}

function on_exit {
    rm -rf $TDIR
}

OUTPUT=$1
GENOME_BWA=$2
CLIPSEQ1=$3
CLIPSEQ2=$4
BASE1=$5
SAMPLENAME=$6
VERSION=$7
BWA_THREADS=$8
shift 8
BWA_OPTS="$@"

LOG=${OUTPUT}.log

if [ -e /fscratch ]; then
    TDIR=/fscratch/socci/PEMapper/$(uuid_short)
else
    TDIR=/scratch/socci/PEMapper/$(uuid_short)
fi

echo TDIR=$TDIR | tee $LOG
mkdir -vp $TDIR | tee -a $LOG

trap on_exit EXIT

bwa mem $BWA_OPTS -t $BWA_THREADS -H $VERSION $GENOME_BWA $CLIPSEQ1 $CLIPSEQ2 \
    | picardV2 AddOrReplaceReadGroups MAX_RECORDS_IN_RAM=5000000 CREATE_INDEX=true SO=coordinate \
        LB=$SAMPLENAME PU=${BASE1%%_R1_*} SM=$SAMPLENAME PL=illumina CN=GCL \
        I=/dev/stdin \
        O=$TDIR/$(basename $OUTPUT)


md5sum $TDIR/$(basename $OUTPUT) | tee -a $LOG
rsync -a $TDIR/$(basename $OUTPUT) $(dirname $OUTPUT) | tee -a $LOG
sleep 60
rsync -avP $TDIR/$(basename $OUTPUT) $(dirname $OUTPUT) | tee -a $LOG
md5sum $OUTPUT | tee -a $LOG


