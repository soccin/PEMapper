#!/bin/bash

set -euo pipefail

INPUT=$1
OUTPUT=$2
SAMPLENAME=$3
PU=$4

TDIR=/fscratch/socci/PEMapper/$(uuidgen)
mkdir -vp $TDIR
if [ ! -e $TDIR ]; then
    echo no fscratch, using scratch;
    TDIR=/scratch/socci/PEMapper/$(uuidgen)
    mkdir -vp $TDIR
fi

TBAM=$TDIR/$(basename $INPUT)

samtools view -b -o ${TBAM}.1.bam $INPUT
samtools collate -@ 2 -o ${TBAM}.2.bam ${TBAM}.1.bam
samtools fixmate -@ 2 -m ${TBAM}.2.bam ${TBAM}.3.bam

picard.local AddOrReplaceReadGroups MAX_RECORDS_IN_RAM=5000000 CREATE_INDEX=true SO=coordinate \
    LB=$SAMPLENAME PU=$PU SM=$SAMPLENAME PL=illumina CN=GCL \
    I=${TBAM}.3.bam O=$OUTPUT

rm -vrf $TDIR
