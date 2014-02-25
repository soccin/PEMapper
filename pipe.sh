#!/bin/bash
SDIR="$( cd "$( dirname "$0" )" && pwd )"
source $SDIR/opt/bin/activate
export PATH=$SDIR/bin:$PATH
source $SDIR/bin/sge.sh

SCRIPT_TAG=$(hg tags -R $SDIR | fgrep v_ | head -1 | awk '{print $1}')
SCRIPT_GREV=$(hg id -i -R $SDIR | tr -d "+")
SCRIPT_LREV=$(hg id -n -R $SDIR | tr -d "+")
SCRIPT_VERSION=$SCRIPT_TAG"___"$SCRIPT_LREV":"$SCRIPT_GREV
PIPENAME="PEMapper"

##
# Process command args

TAG=qPEMAP

COMMAND_LINE=$*
function usage {
    echo
    echo "usage: $PIPENAME/pipe.sh [-s SAMPLENAME] GENOME SAMPLEDIR"
    echo "    -g ListGenomes"
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

if [ ! -e $SDIR/lib/genomes/$GENOME ]; then
    echo
    echo GENOME=$GENOME Not Defined
    echo Currently defined genomes
    ls -1 $SDIR/lib/genomes
    echo

    exit
fi

source $SDIR/lib/genomes/$GENOME

SAMPLEDIR=$1
SAMPLEDIR=$(echo $SAMPLEDIR | sed 's/\/$//')
SAMPLEDIRS=$*

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
BWA_VERSION=$(bwa 2>&1 | fgrep Version | awk '{print $2}')

JOBS=""
BAMFILES=""

FASTQFILES=$(find $SAMPLEDIRS -name "*_R1_???.fastq.gz")
for FASTQ1 in $FASTQFILES; do

    FASTQ2=${FASTQ1/_R1_/_R2_}
    BASE1=$(echo $FASTQ1 | tr '/' '_')
    BASE2=$(echo $FASTQ2 | tr '/' '_')
    UUID=$(uuidgen)
    QRUN 2 ${TAG}__01__$UUID \
        clipAdapters.sh $ADAPTER $FASTQ1 $FASTQ2
    CLIPSEQ1=$SCRATCH/${BASE1}___CLIP.fastq
    CLIPSEQ2=$SCRATCH/${BASE2}___CLIP.fastq

    BWA_THREADS=6
    echo -e "@PG\tID:bwa\tVN:$BWA_VERSION" > $SCRATCH/${BASE1%%.fastq*}.sam
    echo -e "@PG\tID:$PIPENAME\tVN:$SCRIPT_VERSION\tCL:$0 ${COMMAND_LINE}" >> $SCRATCH/${BASE1%%.fastq*}.sam
    QRUN $BWA_THREADS ${TAG}__02__$UUID HOLD ${TAG}__01__$UUID \
        bwa mem -t $BWA_THREADS $GENOME_BWA $CLIPSEQ1 $CLIPSEQ2 \>\>$SCRATCH/${BASE1%%.fastq*}.sam

    QRUN 1 ${TAG}__03__$UUID HOLD ${TAG}__02__$UUID VMEM 24G \
        picard.local AddOrReplaceReadGroups CREATE_INDEX=true SO=coordinate \
        LB=$SAMPLENAME PU=${BASE1%%_R1_*} SM=$SAMPLENAME PL=illumina CN=GCL \
        I=$SCRATCH/${BASE1%%.fastq*}.sam O=$SCRATCH/${BASE1%%.fastq*}.bam

    BAMFILES="$BAMFILES $SCRATCH/${BASE1%%.fastq*}.bam"
    JOBS="$JOBS,$JOBID"

done

HOLDIDS=$(echo $JOBS | sed 's/^,//')

INPUTS=$(echo $BAMFILES | tr ' ' '\n' | awk '{print "I="$1}')
mkdir -p out
QRUN 1 ${TAG}__04__MERGE__${SAMPLENAME} HOLD $HOLDIDS VMEM 24G \
    picard.local MergeSamFiles SO=coordinate CREATE_INDEX=true \
    O=out/${SAMPLENAME}.bam $INPUTS

QRUN 1 ${TAG}__05__STATS__${SAMPLENAME} HOLD ${TAG}__04__MERGE__${SAMPLENAME} VMEM 24G \
    picard.local CollectAlignmentSummaryMetrics \
    I=out/${SAMPLENAME}.bam O=out/${SAMPLENAME}___AS.txt \
    R=$GENOME_FASTA

QRUN 1 ${TAG}__05__STATS__${SAMPLENAME} HOLD ${TAG}__04__MERGE__${SAMPLENAME} VMEM 24G \
    picard.local CollectInsertSizeMetrics \
    I=out/${SAMPLENAME}.bam O=out/${SAMPLENAME}___INS.txt \
	H=out/${SAMPLENAME}___INSHist.pdf \
    R=$GENOME_FASTA

QRUN 1 ${TAG}__06__HOLD__${SAMPLENAME} HOLD ${TAG}__05__STATS__${SAMPLENAME} \
	cat out/${SAMPLENAME}___AS.txt \| egrep -v '"(^#|^$)"' \| /home/socci/bin_centos5/transpose.py \>out/${SAMPLENAME}___ASt.txt

