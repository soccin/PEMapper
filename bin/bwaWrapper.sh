#!/bin/bash

# bwaWrapper.sh
    # mem
    # $BWA_OPTS \
    # -t \
    # $BWA_THREADS \
    # $GENOME_BWA \
    # $CLIPSEQ1 \
    # $CLIPSEQ2

nargs=$#

>&2 echo "=============================="
lineCount=$(wc -l ${!nargs} | awk '{print $1}')
>&2 echo "Line count for " ${!nargs} $lineCount

if [ "$lineCount" == "0" ]; then
    >&2 echo "NO READS POST CLIP"
else
    bwa $*
fi
>&2 echo "--"

