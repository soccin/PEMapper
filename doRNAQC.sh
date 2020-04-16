#!/bin/bash

BAM=$1
BUILD=$(~/Code/Gist/getGenomeBuild.sh $BAM)

if [ "$LSF_VERSION" == "" ]; then
        export LSF_VERSION=$(echo $LSF_SERVERDIR | perl -ne 'm|/([^/]+)/linux|;print $1')
        echo setting LSF_VERSION="$LSF_VERSION"
fi

case $LSF_VERSION in
        10.1)
            TIME_FLAG="-W"
            TIME_SHORT="$TIME_FLAG 59"
            TIME_LONG="$TIME_FLAG 359"

        ;;

        9.1)
            TIME_FLAG=""
            TIME_SHORT=""
            TIME_LONG=""
        ;;

        *)
        echo "Error invalid LSF_VERSION ["${LSF_VERSION}"]"
        exit -1
        ;;

esac


case $BUILD in
    mm10)
    REFFLAT=/ifs/work/socci/Pipelines/CBE/rnaseq_pipeline/data/mm10/refFlat__mm10.txt.gz
    ;;

    hg19)
    REFFLAT=/ifs/work/socci/Pipelines/CBE/rnaseq_pipeline/data/hg19/refFlat__hg19.txt.gz
    ;;

    GRCz10)
    REFFLAT=/home/socci/Work/Strand/db/refflat_GRCz10.txt.gz
    ;;

    *)
    echo "UNKNOWN BUILD = "$BUILD
    exit 1
esac

bsub -o LSF/ -J PIC.RNA $TIME_SHORT -R "rusage[mem=36]" \
picard.local CollectRnaSeqMetrics I=$BAM \
    O=$(basename $BAM | sed 's/.bam/___RNAStats_FRTS.txt/') \
    STRAND=FIRST_READ_TRANSCRIPTION_STRAND \
    REF_FLAT=$REFFLAT

bsub -o LSF/ -J PIC.RNA $TIME_SHORT -R "rusage[mem=36]" \
picard.local CollectRnaSeqMetrics I=$BAM \
    O=$(basename $BAM | sed 's/.bam/___RNAStats_SRTS.txt/') \
    STRAND=SECOND_READ_TRANSCRIPTION_STRAND \
    REF_FLAT=$REFFLAT
