#!/bin/bash

INPUT=$1
OUTPUT=$2
SAMPLENAME=$3
PU=$4

samtools view -b -o ${INPUT}.1.bam $INPUT
samtools collate -@ 2 -o ${INPUT}.2.bam ${INPUT}.1.bam
samtools fixmate -@ 2 -m ${INPUT}.2.bam ${INPUT}.3.bam

picard.local AddOrReplaceReadGroups MAX_RECORDS_IN_RAM=5000000 CREATE_INDEX=true SO=coordinate \
    LB=$SAMPLENAME PU=$PU SM=$SAMPLENAME PL=illumina CN=GCL \
    I=${INPUT}.3.bam O=$OUTPUT
