#!/bin/bash

##
# DISABLED on IRIS. Everything this script points at is dead:
#
#   ~/Code/Gist/getGenomeBuild.sh    personal checkout, not in this repo
#   /ifs/work/socci/...refFlat...    retired path
#   bsub -R "rusage[mem=36]"         LSF; there is no bsub on IRIS
#
# It is a standalone helper and is not called by pipe.sh, so nothing in
# the pipeline is affected. To bring it back: repoint the refFlat files
# at /data1/core001/rsrc, replace getGenomeBuild.sh, and convert the two
# bsub calls to QRUN (see bin/slurm.sh). Remove this block when done.
#
cat >&2 <<'EOM'

  doRNAQC.sh is disabled: its reference paths and its LSF bsub calls
  have not been ported to IRIS. Nothing was submitted. See the comment
  at the top of this script for what needs fixing.

EOM
exit 0

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
