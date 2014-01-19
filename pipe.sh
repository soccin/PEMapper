#!/bin/bash
SDIR="$( cd "$( dirname "$0" )" && pwd )"
source $SDIR/opt/bin/activate
export PATH=$SDIR/bin:$PATH
source $SDIR/bin/sge.sh

##
# Process command args

TAG=qPEMAP

COMMAND_LINE=$*
function usage {
    echo
    echo "usage: rnaSEQ/pipe.sh [-s SAMPLENAME] GENOME SAMPLEDIR"
    echo
    exit
}

SAMPLENAME="__NotDefined"
while getopts "s:h" opt; do
    case $opt in
        s)
            SAMPLENAME=$OPTARG
            ;;
        h)
            usage
            ;;
        \?)
            usage
            ;;
    esac
done

shift $((OPTIND - 1))
if [ "$#" -lt "2" ]; then
    usage
fi

GENOME=$1
SAMPLEDIR=$2
SAMPLEDIR=$(echo $SAMPLEDIR | sed 's/\/$//')

if [ $SAMPLENAME == "__NotDefined" ]; then
    SAMPLENAME=$(basename $SAMPLEDIR)
fi

echo SAMPLENAME=$SAMPLENAME
TAG=${TAG}_$$_$SAMPLENAME

export SCRATCH=$(pwd)/_scratch
mkdir -p $SCRATCH

##
# HiSeq TrueSeq maximal common adapter

ADAPTER="AGATCGGAAGAGC"

for FASTQ in $SAMPLEDIR/*_R1_???.fastq.gz; do
    BASE=$(basename $FASTQ)
    QRUN 2 ${TAG}__01__$BASE \
        clipAdapters.sh $ADAPTER $FASTQ ${FASTQ/_R1_/_R2_}

    CLIPSEQ1=$SCRATCH/$(basename $FASTQ)___CLIP.fastq
    CLIPSEQ2=$SCRATCH/$(basename ${FASTQ/_R1_/_R2_})___CLIP.fastq
    #QRUN 3 ${TAG}__02__$BASE HOLD ${TAG}__01__$BASE runBwa.sh $CLIPSEQ1 $CLIPSEQ2
done

