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

if [ ! -e $SDIR/lib/genomes/$GENOME ]; then
    echo
    echo GENOME=$GENOME Not Defined
    echo Currently defined genomes
    ls $SDIR/lib/genomes
    echo

    exit
fi

source $SDIR/lib/genomes/$GENOME

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

SAMFILES=""
for FASTQ in $SAMPLEDIR/*_R1_???.fastq.gz; do
    BASE=$(basename $FASTQ)
    QRUN 2 ${TAG}__01__$BASE \
        clipAdapters.sh $ADAPTER $FASTQ ${FASTQ/_R1_/_R2_}

    CLIPSEQ1=$SCRATCH/$(basename $FASTQ)___CLIP.fastq
    CLIPSEQ2=$SCRATCH/$(basename ${FASTQ/_R1_/_R2_})___CLIP.fastq
    BWA_THREADS=3
    QRUN $BWA_THREADS ${TAG}__02__$BASE HOLD ${TAG}__01__$BASE \
        bwa mem -C -t $BWA_THREADS $GENOME_BWA $CLIPSEQ1 $CLIPSEQ2 \> $SCRATCH/${BASE%%.fastq*}.sam
    SAMFILES="$SAMFILES $SCRATCH/${BASE%%.fastq*}.sam"
done

echo $SAMFILES