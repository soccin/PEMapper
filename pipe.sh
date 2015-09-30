#!/bin/bash
SDIR="$( cd "$( dirname "$0" )" && pwd )"
export PATH=$SDIR/bin:$PATH
source $SDIR/bin/lsf.sh

SCRIPT_VERSION=$(git --git-dir=$SDIR/.git --work-tree=$SDIR describe --always --long)
PIPENAME="PEMapper"

##
# Process command args

TAG=qPEMAP

COMMAND_LINE=$*
function usage {
    echo
    echo "usage: $PIPENAME/pipe.sh [-s SAMPLENAME] GENOME SAMPLEDIR"
    echo "version=$SCRIPT_VERSION"
    echo "    -g ListGenomes"
    echo
    exit
}

SAMPLENAME="__NotDefined"
while getopts "s:hg" opt; do
    case $opt in
        s)
            SAMPLENAME=$OPTARG
            ;;
        h)
            usage
            ;;
        g)
            echo Currently defined genomes
            echo
            ls -1 $SDIR/lib/genomes
            echo
            exit
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
shift

if [ -e $SDIR/lib/genomes/$GENOME ]; then
    source $SDIR/lib/genomes/$GENOME
else
    if [ -e $GENOME ]; then
        source $GENOME
    else
        echo
        echo GENOME=$GENOME Not Defined
        echo "Currently available (builtin) genomes"
        ls -1 $SDIR/lib/genomes
        echo
        exit
    fi
fi


SAMPLEDIR=$1
SAMPLEDIR=$(echo $SAMPLEDIR | sed 's/\/$//' | sed 's/;.*//')

SAMPLEDIRS=$*
SAMPLEDIRS=$(echo $SAMPLEDIRS | tr ';' ' ')

if [ $SAMPLENAME == "__NotDefined" ]; then
    SAMPLENAME=$(basename $SAMPLEDIR)
    if [ "$SAMPLENAME" == "" ]; then
        echo "Error in sample name processing; Null sample name"
        exit
    fi
fi

echo SAMPLENAME=$SAMPLENAME
TAG=${TAG}_$$_$SAMPLENAME

export SCRATCH=$(pwd)/_scratch
mkdir -p $SCRATCH


##
# HiSeq TrueSeq maximal common adapter

ADAPTER="AGATCGGAAGAGC"
BWA_VERSION=$(bwa 2>&1 | fgrep Version | awk '{print $2}')

JOBS=""
BAMFILES=""

FASTQFILES=$(find -L $SAMPLEDIRS -name "*_R1_???.fastq.gz")
echo "FASTQFILES="$FASTQFILES

if [ "$FASTQFILES" == "" ]; then
    echo "Can not find any FASTQFILES"
    exit
fi

for FASTQ1 in $FASTQFILES; do

    FASTQ2=${FASTQ1/_R1_/_R2_}
    BASE1=$(echo $FASTQ1 | tr '/' '_')
    BASE2=$(echo $FASTQ2 | tr '/' '_')
    UUID=$(uuidgen)

    # Get readlength
    ONE_HALF_READLENGTH=$(zcat $FASTQ1 | head -40 | xargs -n 4 | awk '{print $2}' | wc | awk '{printf("%d\n",($3/10-1)/2)}')
    echo ONE_HALF_READLENGTH=$ONE_HALF_READLENGTH
    export MINLENGTH=$ONE_HALF_READLENGTH

    QRUN 2 ${TAG}__01__$UUID VMEM 5 \
        clipAdapters.sh $ADAPTER $FASTQ1 $FASTQ2
    CLIPSEQ1=$SCRATCH/${BASE1}___CLIP.fastq
    CLIPSEQ2=$SCRATCH/${BASE2}___CLIP.fastq

    BWA_THREADS=6
    echo -e "@PG\tID:$PIPENAME\tVN:$SCRIPT_VERSION\tCL:$0 ${COMMAND_LINE}" >> $SCRATCH/${BASE1%%.fastq*}.sam

    QRUN $BWA_THREADS ${TAG}__02__$UUID HOLD ${TAG}__01__$UUID \
        bwa mem -t $BWA_THREADS $GENOME_BWA $CLIPSEQ1 $CLIPSEQ2 \>\>$SCRATCH/${BASE1%%.fastq*}.sam

    QRUN 2 ${TAG}__03__$UUID HOLD ${TAG}__02__$UUID VMEM 26 \
        picard.local AddOrReplaceReadGroups CREATE_INDEX=true SO=coordinate \
        LB=$SAMPLENAME PU=${BASE1%%_R1_*} SM=$SAMPLENAME PL=illumina CN=GCL \
        I=$SCRATCH/${BASE1%%.fastq*}.sam O=$SCRATCH/${BASE1%%.fastq*}.bam

    BAMFILES="$BAMFILES $SCRATCH/${BASE1%%.fastq*}.bam"
    JOBS="$JOBS,$JOBID"

    exit

done

HOLDIDS=$(echo $JOBS | sed 's/^,//')

INPUTS=$(echo $BAMFILES | tr ' ' '\n' | awk '{print "I="$1}')
mkdir -p out
QRUN 2 ${TAG}__04__MERGE__${SAMPLENAME} HOLD $HOLDIDS VMEM 26 \
    picard.local MergeSamFiles SO=coordinate CREATE_INDEX=true \
    O=out/${SAMPLENAME}.bam $INPUTS

QRUN 2 ${TAG}__05__STATS__${SAMPLENAME} HOLD ${TAG}__04__MERGE__${SAMPLENAME} VMEM 26 \
    picard.local CollectAlignmentSummaryMetrics \
    I=out/${SAMPLENAME}.bam O=out/${SAMPLENAME}___AS.txt \
    R=$GENOME_FASTA

QRUN 2 ${TAG}__05__STATS__${SAMPLENAME} HOLD ${TAG}__04__MERGE__${SAMPLENAME} VMEM 26 \
    picard.local CollectInsertSizeMetrics \
    I=out/${SAMPLENAME}.bam O=out/${SAMPLENAME}___INS.txt \
	H=out/${SAMPLENAME}___INSHist.pdf \
    R=$GENOME_FASTA

QRUN 1 ${TAG}__06__HOLD__${SAMPLENAME} HOLD ${TAG}__05__STATS__${SAMPLENAME} \
	cat out/${SAMPLENAME}___AS.txt \| egrep -v '"(^#|^$)"' \| /home/socci/bin/transpose.py \>out/${SAMPLENAME}___ASt.txt

