#!/bin/bash

set -euo pipefail

BAM=$1
BUILD=$(~/Code/Gist/getGenomeBuild.sh $BAM)

case $BUILD in
    mm10)
    REFFLAT=/ifs/work/socci/Pipelines/CBE/rnaseq_pipeline/data/refFlat__mm10.txt.gz
    ;;

    hg19)
    REFFLAT=/ifs/work/socci/Pipelines/CBE/rnaseq_pipeline/data/refFlat__hg19.txt.gz
    ;;

    *)
    echo "UNKNOWN BUILD = "$BUILD
    exit 1
esac

bsub -o LSF/ -J PIC.RNA -We 59 -R "rusage[mem=36]" \
picard.local CollectRnaSeqMetrics I=$BAM \
    O=$(basename $BAM | sed 's/.bam/___RNAStats_FRTS.txt/') \
    STRAND=FIRST_READ_TRANSCRIPTION_STRAND \
    REF_FLAT=$REFFLAT

bsub -o LSF/ -J PIC.RNA -We 59 -R "rusage[mem=36]" \
picard.local CollectRnaSeqMetrics I=$BAM \
    O=$(basename $BAM | sed 's/.bam/___RNAStats_SRTS.txt/') \
    STRAND=SECOND_READ_TRANSCRIPTION_STRAND \
    REF_FLAT=$REFFLAT
