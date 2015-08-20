#!/bin/bash

#GENOME_FASTQ=/ifs/data/bio/Genomes/M.musculus/mm9/mouse_mm9__All.fa
#GENESFILE=/home/socci/Work/SeqAna/Pipelines/db/MM9/refFlat__mm9.txt.gz
#RIBOFILE=/home/socci/Work/SeqAna/Pipelines/db/MM9/ribosomal.interval_file

GENOME_FASTQ=/ifs/data/bio/Genomes/H.sapiens/hg19/human_hg19_FULL.fa
GENESFILE=/home/socci/Work/SeqAna/Pipelines/db/HG19/refFlat__hg19.txt.gz
RIBOFILE=/home/socci/Work/SeqAna/Pipelines/Mappers/PEMapper/lib/genomes/human_hg19__ribosomal.interval_file

BAM=$1
BASE=$(basename $BAM | sed 's/.bam//')
source ~/Work/SGE/sge.sh

if [ "" ]; then
echo "SHOULD NOT GET HERE"
exit
qsub -pe alloc 3 -l virtual_free=13G -N PIC ~/Work/SGE/qCMD \
	picard_1119 CollectRnaSeqMetrics R=$GENOME_FASTQ \
	RIBOSOMAL_INTERVALS=$RIBOFILE \
	REF_FLAT=$GENESFILE \
	STRAND=NONE \
	I=$BAM \
	O=${BASE}_RNAMetrics.txt
fi
	
#RIBOSOMAL_INTERVALS=$RIBOFILE \

qsub -pe alloc 3 -l virtual_free=13G -N PIC ~/Work/SGE/qCMD \
	picard_1119 CollectRnaSeqMetrics R=$GENOME_FASTQ \
	REF_FLAT=$GENESFILE \
	STRAND=SECOND_READ_TRANSCRIPTION_STRAND \
	I=$BAM \
	O=${BASE}_RNAMetrics_SRTS.txt

qsub -pe alloc 3 -l virtual_free=13G -N PIC ~/Work/SGE/qCMD \
	picard_1119 CollectRnaSeqMetrics R=$GENOME_FASTQ \
	REF_FLAT=$GENESFILE \
	STRAND=FIRST_READ_TRANSCRIPTION_STRAND \
	I=$BAM \
	O=${BASE}_RNAMetrics_FRTS.txt


