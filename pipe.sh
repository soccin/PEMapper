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
BWA_VERSION=$(bwa 2>&1 | fgrep Version | awk '{print $2}')

JOBS=""
BAMFILES=""
for FASTQ in $SAMPLEDIR/*_R1_???.fastq.gz; do
    BASE=$(basename $FASTQ)
    QRUN 2 ${TAG}__01__$BASE \
        clipAdapters.sh $ADAPTER $FASTQ ${FASTQ/_R1_/_R2_}

    CLIPSEQ1=$SCRATCH/$(basename $FASTQ)___CLIP.fastq
    CLIPSEQ2=$SCRATCH/$(basename ${FASTQ/_R1_/_R2_})___CLIP.fastq
    BWA_THREADS=3
    echo -e "@PG\tID:bwa\tVN:$BWA_VERSION" > $SCRATCH/${BASE%%.fastq*}.sam
    echo -e "@PG\tID:$PIPENAME\tVN:$SCRIPT_VERSION\tCL:$0 ${COMMAND_LINE}" >> $SCRATCH/${BASE%%.fastq*}.sam
    QRUN $BWA_THREADS ${TAG}__02__$BASE HOLD ${TAG}__01__$BASE \
        bwa mem -t $BWA_THREADS $GENOME_BWA $CLIPSEQ1 $CLIPSEQ2 \>\>$SCRATCH/${BASE%%.fastq*}.sam

    QRUN 1 ${TAG}__03__$BASE HOLD ${TAG}__02__$BASE VMEM 24G \
        picard AddOrReplaceReadGroups CREATE_INDEX=true SO=coordinate \
        LB=$SAMPLENAME PU=$SAMPLENAME SM=$SAMPLENAME PL=illumina CN=GCL \
        I=$SCRATCH/${BASE%%.fastq*}.sam O=$SCRATCH/${BASE%%.fastq*}.bam

    BAMFILES="$BAMFILES $SCRATCH/${BASE%%.fastq*}.bam"
    JOBS="$JOBS,$JOBID"
done

HOLDIDS=$(echo $JOBS | sed 's/^,//')

INPUTS=$(echo $BAMFILES | tr ' ' '\n' | awk '{print "I="$1}')
mkdir -p out
QRUN 1 ${TAG}__04__MERGE__${SAMPLENAME} HOLD $HOLDIDS VMEM 24G \
    picard MergeSamFiles SO=coordinate CREATE_INDEX=true \
    O=out/${SAMPLENAME}.bam $INPUTS

QRUN 1 ${TAG}__05__STATS__${SAMPLENAME} HOLD ${TAG}__04__MERGE__${SAMPLENAME} VMEM 24G \
    picard CollectAlignmentSummaryMetrics \
    I=out/${SAMPLENAME}.bam O=out/${SAMPLENAME}___AS.txt \
    R=$GENOME_FASTA

