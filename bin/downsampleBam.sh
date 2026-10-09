#!/bin/bash

#
# Downsample a BAM to 1/DOWN of its read pairs with picard DownsampleSam.
#
#   downsampleBam.sh [-s|--submit] DOWN BAM
#
# DO NOT run this script with sbatch. It has no #SBATCH header; use -s,
# which submits it to the cluster with a partition and time limit picked
# from the size of BAM. Without -s it runs in the current shell.
#
# Writes out/picard/DSB/<SM>/<basename BAM .bam>.dn_<DOWN>.bam and its
# .bai, relative to the current directory. SM is the sample tag of the
# BAM's @RG lines and must be unique. With -s the job log is
# SLM/DSB_<jobid>.out, relative to the current directory.
#
# Slurm writes nothing of its own into the log, so with -s the log ends
# with a "#DSB_EXIT=<rc>" trailer. A missing trailer is a failure too: a
# job Slurm kills for memory or walltime never gets to write it. List
# every job that did not succeed with
#
#   grep -L "#DSB_EXIT=0" SLM/DSB_*.out
#
# -s asks for -c 2 and 32G whatever the size, matching a LONG picard QRUN
# call site: -c 2 for the GC thread cap and 32G, which bin/picardJvm.sh
# turns into -Xmx23g. DownsampleSam streams the BAM, so neither grows
# with it.
#

#
# 35 GiB is roughly 80% of the smallest KEJ WGS BAM. A BAM under it gets
# 2h on cpushort or cmobic_short, anything else 3 days on cmobic_cpu.
# cpushort's MaxTime is exactly 2:00:00 and it pins its own qos, so the
# short tier must not set --qos.
#
SIZE_CUTOFF=$((35 * 1024 ** 3))
SHORT_ARGS="-p cpushort,cmobic_short -t 2:00:00"
LONG_ARGS="-p cmobic_cpu -t 3-00:00:00 --qos=priority"

usage() {
    echo "usage: downsampleBam.sh [-s|--submit] DOWN BAM"
    echo "    keep 1/DOWN of the reads; DOWN is an integer > 1"
    echo "    -s|--submit  submit to the cluster, time limit set by BAM size"
    echo "    do not run this script with sbatch; use -s"
}

SDIR="$( cd "$( dirname "$0" )" && pwd )"

if [ ! -x "$SDIR/picard.local" ]; then
    if [ -n "$SLURM_JOB_ID" ]; then
        echo "FATAL ERROR: this script cannot be run with sbatch; use -s"
    else
        echo "FATAL ERROR: cannot find picard.local in SDIR [$SDIR]"
    fi
    exit 1
fi

SUBMIT=No
case "$1" in
    -s|--submit) SUBMIT=Yes; shift ;;
esac

if [ "$#" != "2" ]; then
    usage
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
# samtools comes from Lmod. module is normally inherited as an exported
# function; source the init script in case this shell did not get it.
#
if [ "$(type -t module)" != "function" ]; then
    . /etc/profile.d/modules.sh
fi

module load samtools
if ! command -v samtools >/dev/null; then
    echo "FATAL ERROR: module load samtools failed"
    exit 1
fi

#
# Without pipefail a samtools failure here would read as an empty SM.
#
set -o pipefail

SM=$(samtools view -H $BAM \
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

if [ "$SUBMIT" == "Yes" ]; then

    SIZE=$(stat -L -c %s $BAM)
    if [ "$SIZE" -lt "$SIZE_CUTOFF" ]; then
        TIER_ARGS=$SHORT_ARGS
    else
        TIER_ARGS=$LONG_ARGS
    fi

    #
    # The job runs this script again by absolute path, so $0 leads back
    # to bin/. Keep the BAM's own basename; it names the output.
    #
    ABAM=$(cd "$(dirname "$BAM")" && pwd)/$(basename "$BAM")

    #
    # Slurm does not create the -o directory; a job whose log directory
    # is missing fails with no log at all.
    #
    mkdir -p SLM

    JOBID=$(sbatch --parsable -A core001 $TIER_ARGS -N 1 -n 1 -c 2 --mem=32G \
        -J DSB -o SLM/DSB_%j.out \
        --wrap "$SDIR/downsampleBam.sh $DOWN $ABAM; RC=\$?; echo \"#DSB_EXIT=\$RC\"; exit \$RC")
    RC=$?

    if [ "$RC" != "0" ]; then
        echo "FATAL ERROR: sbatch failed rc=[$RC]"
        exit 1
    fi

    echo JOBID=$JOBID SM=$SM SIZE=$SIZE
    echo SLURM=$TIER_ARGS
    exit 0

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
