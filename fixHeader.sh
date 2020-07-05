#!/bin/bash
SDIR="$( cd "$( dirname "$0" )" && pwd )"
export PATH=$SDIR/bin:$PATH

BAM=$1

samtools view -H $BAM | egrep -v "^@(SQ)" >${BAM}.hdr

cat ${GENOME_FASTA/.fa/.dict} | egrep -v "^@HD" >>${BAM}.hdr

picardV2 ReplaceSamHeader I=$BAM O=${BAM/.bam/_FixHdr.bam} HEADER=${BAM}.hdr

picardV2 BuildBamIndex I=${BAM/.bam/_FixHdr.bam}
