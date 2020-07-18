#!/bin/bash
SDIR="$( cd "$( dirname "$0" )" && pwd )"
export PATH=$SDIR/bin:$PATH

GENOME_FASTA=$1
BAM=$2

MD5_0=$(cat ${BAM}.md5 | awk '{print $1}')

while [ ! -e $BAM ]; do
    echo $BAM does not exists sleep
    sleep 60
done

MD5_1=$(md5sum ${BAM} | awk '{print $1}')

while [ "$MD5_1" != "$MD5_0" ]; do
    echo MD5_0=$MD5_0
    echo MD5_1=$MD5_1
    echo Sleep
    MD5_1=$(md5sum ${BAM} | awk '{print $1}')
    sleep 60
done

echo Final MD5_0=$MD5_0
echo Final MD5_1=$MD5_1

samtools view -H $BAM | egrep -v "^@(SQ)" >${BAM}.hdr

echo GENOME_FASTA=$GENOME_FASTA
echo GENOME_DICT=${GENOME_FASTA/.fa/.dict}

cat ${GENOME_FASTA/.fa/.dict} | egrep -v "^@HD" >>${BAM}.hdr

picardV2 ReplaceSamHeader I=$BAM O=${BAM/.bam/_FixHdr.bam} HEADER=${BAM}.hdr

picardV2 BuildBamIndex I=${BAM/.bam/_FixHdr.bam}

