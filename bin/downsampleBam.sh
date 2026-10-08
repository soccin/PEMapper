#!/bin/bash
#SBATCH -A core001
#SBATCH -p cmobic_cpu
#SBATCH -t 3-00:00:00
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -c 2
#SBATCH --mem=32G
#SBATCH -J DSB
#SBATCH -o DSB_%j.out

#
# Downsample a BAM to 1/DOWN of its read pairs with picard DownsampleSam.
#
#   downsampleBam.sh DOWN BAM
#   sbatch bin/downsampleBam.sh DOWN BAM
#
# Writes out/picard/DSB/<SM>/<basename BAM .bam>.dn_<DOWN>.bam and its
# .bai, relative to the current directory. SM is the sample tag of the
# BAM's @RG lines and must be unique.
#
# The #SBATCH lines match a LONG picard QRUN call site: -c 2 for the GC
# thread cap and 32G, which bin/picardJvm.sh turns into -Xmx23g.
#

SDIR="$( cd "$( dirname "$0" )" && pwd )"

#
# sbatch runs a copy of this script out of the slurmd spool directory, so
# $0 does not lead back to bin/. Ask slurm for the path that was submitted.
#
if [ ! -x "$SDIR/picard.local" ] && [ -n "$SLURM_JOB_ID" ]; then
    SCRIPT=$(scontrol show job $SLURM_JOB_ID \
        | awk '$1 ~ /^Command=/ {sub(/^Command=/, "", $1); print $1}')
    SDIR="$( cd "$( dirname "$SCRIPT" )" && pwd )"
fi

if [ ! -x "$SDIR/picard.local" ]; then
    echo "FATAL ERROR: cannot find picard.local in SDIR [$SDIR]"
    exit 1
fi

if [ "$#" != "2" ]; then
    echo "usage: downsampleBam.sh DOWN BAM"
    echo "    keep 1/DOWN of the reads; DOWN is an integer > 1"
    exit 1
fi

DOWN=$1
BAM=$2

if [[ ! "$DOWN" =~ ^[1-9][0-9]*$ ]] || [ "$DOWN" -le 1 ]; then
    echo "FATAL ERROR: DOWN must be an integer > 1 [$DOWN]"
    exit 1
fi

if [[ "$BAM" != *.bam ]] || [ ! -s "$BAM" ]; then
    echo "FATAL ERROR: missing, empty or non .bam input [$BAM]"
    exit 1
fi

#
# Without pipefail a picard failure here would read as an empty SM.
#
set -o pipefail

SM=$($SDIR/picard.local ViewSam I=$BAM HEADER_ONLY=true \
        ALIGNMENT_STATUS=All PF_STATUS=All \
    | awk -F'\t' '$1 == "@RG" {
        for(i = 2; i <= NF; i++) if($i ~ /^SM:/) print substr($i, 4)
      }' \
    | sort -u)
RC=$?

if [ "$RC" != "0" ]; then
    echo "FATAL ERROR: cannot read the header of [$BAM] rc=[$RC]"
    exit 1
fi

if [ "$SM" == "" ]; then
    echo "FATAL ERROR: no SM tag in the @RG lines of [$BAM]"
    exit 1
fi

if [ "$(echo "$SM" | wc -l)" != "1" ]; then
    echo "FATAL ERROR: more than one SM tag in [$BAM]:" $SM
    exit 1
fi

P=$(awk -v d=$DOWN 'BEGIN {printf "%.10g", 1/d}')

ODIR=out/picard/DSB/$SM
OBAM=$ODIR/$(basename $BAM .bam).dn_${DOWN}.bam
OBAI=${OBAM%.bam}.bai

echo SDIR=$SDIR
echo BAM=$BAM SM=$SM DOWN=$DOWN P=$P
echo OBAM=$OBAM

mkdir -p $ODIR

$SDIR/picard.local DownsampleSam I=$BAM O=$OBAM P=$P CREATE_INDEX=true
RC=$?

if [ "$RC" != "0" ]; then
    echo "FATAL ERROR: DownsampleSam failed rc=[$RC]"
    exit $RC
fi

#
# CREATE_INDEX only indexes coordinate sorted output, and picard says
# nothing when it skips it.
#
if [ ! -s "$OBAI" ]; then
    echo "FATAL ERROR: no index written [$OBAI]; is the input coordinate sorted?"
    exit 1
fi
