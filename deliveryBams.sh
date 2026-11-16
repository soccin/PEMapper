#!/bin/bash

#
# deliveryBams.sh -- deliver the BAMs and picard metrics of a finished
# PEMapper run to the BIC delivery area
#
# usage:
#   deliveryBams.sh [-n] [-i OUTDIR] /path/to/delivery/Proj_<no>[/r_NNN]
#   deliveryBams.sh [-n] [-i OUTDIR] -d|--default
#
# Run from the folder that holds the out___* folder of the run. Every
# sample of OUTDIR (OUTDIR/<genome>/<sample>/) is delivered as
#
#   DELIVERY/r_NNN/bams/<genome>/<sample>/<sample>___MD.{bam,bai}
#   DELIVERY/r_NNN/metrics/<genome>/<sample>/<sample>___{AS,ASt,MD,INS}.txt
#   DELIVERY/r_NNN/metrics/<genome>/<sample>/<sample>___INSHist.pdf
#
#   -i OUTDIR       the out___* folder to deliver; needed only when
#                   there is more than one
#   -d, --default   deliver to DROOT/<pi>/<invest>/Proj_<no>, taken
#                   from the path .../Users/<Pi>/<Invest>/Proj_<no>/...
#                   of the current folder (lowercased but for the
#                   project)
#   -n, --dry-run   print the commands that write to the delivery area
#                   instead of running them
#
# Nothing is delivered unless every sample has a RUNSTATUS.txt saying
# "PEMAP STATUS: OK" and all the files above.
#
# Without a trailing r_NNN the run folder is the one after the highest
# r_NNN in the delivery folder, else r_001. An existing r_NNN can be
# given to add files to it; nothing in it is deleted.
#
# DROOT is /data1/core002/res/bic/results. Every write to the delivery
# area runs as the service account svc_core001_bot01 (dzdo). Unlike
# the ATAC-seq deliverResults.sh, this script does not register the
# run with the bicdelivery permissions database and writes no email.
#

set -euo pipefail

BOT_USER=svc_core001_bot01
DROOT=/data1/core002/res/bic/results

METRICS_SUFFIXES=(___AS.txt ___ASt.txt ___MD.txt ___INS.txt ___INSHist.pdf)
BAM_SUFFIXES=(___MD.bam ___MD.bai)

fatal() {
    echo
    echo "    FATAL ERROR: $*"
    echo
    exit 1
}

#
# The physical path, so the project and the files given to the service
# account do not depend on a symlink it may not be able to follow.
#
CWD=$(pwd -P)

PROJ=""
IFS=/ read -r -a PARTS <<< "$CWD"
for p in "${PARTS[@]}"; do
    if [[ "$p" == Proj_* ]]; then
        PROJ=$p
    fi
done

#
# Default delivery path from .../Users/Aa/BBB/Proj_nnnnn/...
# -> aa/bbb/Proj_nnnnn; the third component must be the project.
#
DPATH=""
if [[ "$CWD" == *"/Users/"* && -n "$PROJ" ]]; then
    rest="${CWD#*/Users/}"
    IFS=/ read -r u1 u2 proj _ <<< "$rest"
    if [[ -n "$u1" && -n "$u2" && "$proj" == "$PROJ" ]]; then
        DPATH="${u1,,}/${u2,,}/$proj"
    fi
fi

usage() {
    echo
    echo "usage: deliveryBams.sh [-n] [-i OUTDIR] /path/to/delivery/Proj_<no>[/r_NNN]"
    echo "       deliveryBams.sh [-n] [-i OUTDIR] -d|--default"
    echo
    echo "    -i OUTDIR       out___* folder to deliver (default: the only one here)"
    echo "    -n, --dry-run   print the delivery commands, do not run them"
    echo
    echo "    default: ${DPATH:+$DROOT/}${DPATH:-(none)}"
    echo
}

ODIR=""
INDIR=""
USE_DEFAULT=0
DRYRUN=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--default)
            USE_DEFAULT=1
            ;;
        -n|--dry-run)
            DRYRUN=1
            ;;
        -i)
            if [[ $# -lt 2 ]]; then
                echo "-i needs an OUTDIR"
                usage
                exit 1
            fi
            INDIR="$2"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            if [[ -n "$ODIR" ]]; then
                echo "Only one delivery folder may be given"
                usage
                exit 1
            fi
            ODIR="$1"
            ;;
    esac
    shift
done

if [[ "$USE_DEFAULT" -eq 1 && -n "$ODIR" ]]; then
    echo "Give a delivery folder or -d, not both"
    usage
    exit 1
fi

if [[ "$USE_DEFAULT" -eq 1 ]]; then
    if [[ -z "$DPATH" ]]; then
        fatal "no default delivery path for $CWD (not .../Users/<Pi>/<Invest>/Proj_<no>/...)"
    fi
    ODIR="$DROOT/$DPATH"
fi

if [[ -z "$ODIR" ]]; then
    usage
    exit 1
fi

asbot() {
    if [[ "$DRYRUN" -eq 1 ]]; then
        echo "DRYRUN: dzdo -u $BOT_USER ${*@Q}"
    else
        dzdo -u "$BOT_USER" "$@"
    fi
}

##
# The run: OUTDIR/<genome>/<sample>/

if [[ -z "$INDIR" ]]; then
    shopt -s nullglob
    CANDS=(out___*/)
    shopt -u nullglob
    if [[ ${#CANDS[@]} -eq 0 ]]; then
        fatal "no out___* folder in $CWD"
    fi
    if [[ ${#CANDS[@]} -gt 1 ]]; then
        fatal "more than one out___* folder (${CANDS[*]%/}); pick one with -i"
    fi
    INDIR=${CANDS[0]}
fi

if [[ ! -d "$INDIR" ]]; then
    fatal "$INDIR is not a folder"
fi
INDIR=$(realpath "$INDIR")

shopt -s nullglob
SAMPLE_DIRS=("$INDIR"/*/*/)
shopt -u nullglob
SAMPLE_DIRS=("${SAMPLE_DIRS[@]%/}")

if [[ ${#SAMPLE_DIRS[@]} -eq 0 ]]; then
    fatal "no <genome>/<sample> folders in $INDIR"
fi

#
# Check every sample before anything is copied, and report all the
# problems at once.
#
ERRORS=()
for sdir in "${SAMPLE_DIRS[@]}"; do
    sample=${sdir##*/}
    status=$sdir/RUNSTATUS.txt
    if [[ ! -s "$status" ]]; then
        ERRORS+=("$sdir: no RUNSTATUS.txt")
    elif ! grep -q "^PEMAP STATUS: OK" "$status"; then
        ERRORS+=("$sdir: $(grep -m1 '^PEMAP STATUS:' "$status" || echo 'no PEMAP STATUS line')")
    fi
    for sfx in "${BAM_SUFFIXES[@]}" "${METRICS_SUFFIXES[@]}"; do
        if [[ ! -s "$sdir/$sample$sfx" ]]; then
            ERRORS+=("$sdir: missing $sample$sfx")
        fi
    done
done

if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo
    for e in "${ERRORS[@]}"; do
        echo "    $e"
    done
    fatal "${#ERRORS[@]} problem(s) above; nothing delivered"
fi

##
# Run folder: a trailing r_NNN as given, else the next one in ODIR

ODIR=$(realpath -m "$ODIR")
if [[ "$ODIR" =~ /(r_[0-9]+)$ ]]; then
    CURRDIR=${BASH_REMATCH[1]}
    ODIR=${ODIR%/*}
else
    CURRDIR=""
fi

#
# The deepest existing folder of ODIR must be readable by us; else
# the run folders in it could exist unseen, and r_001 would be picked
# or files added to a run folder without the note below.
#
seen=$ODIR
while [[ -n "$seen" && ! -e "$seen" ]]; do
    seen=${seen%/*}
done
seen=${seen:-/}
if [[ ! -r "$seen" || ! -x "$seen" ]]; then
    fatal "cannot read $seen, so cannot tell what is in $ODIR"
fi

if [[ -z "$CURRDIR" ]]; then
    last=0
    for d in "$ODIR"/r_[0-9]*; do
        n=${d##*/r_}
        if [[ -d "$d" && "$n" =~ ^[0-9]+$ ]] && ((10#$n > last)); then
            last=$((10#$n))
        fi
    done
    CURRDIR=$(printf 'r_%03d' $((last + 1)))
fi
DEST=$ODIR/$CURRDIR

echo "INDIR=$INDIR"
echo "SAMPLES=${#SAMPLE_DIRS[@]}"
echo "ODIR=$ODIR"
echo "CURRDIR=$CURRDIR"
if [[ -e "$DEST" ]]; then
    echo "NOTE: $DEST exists; files are added to it"
fi
echo

##
# Copy

for sdir in "${SAMPLE_DIRS[@]}"; do
    sample=${sdir##*/}
    genome=${sdir%/*}
    genome=${genome##*/}

    bams=()
    for sfx in "${BAM_SUFFIXES[@]}"; do
        bams+=("$sdir/$sample$sfx")
    done
    metrics=()
    for sfx in "${METRICS_SUFFIXES[@]}"; do
        metrics+=("$sdir/$sample$sfx")
    done

    asbot mkdir -p "$DEST/bams/$genome/$sample" "$DEST/metrics/$genome/$sample"
    asbot rsync -aP "${bams[@]}" "$DEST/bams/$genome/$sample/"
    asbot rsync -aP "${metrics[@]}" "$DEST/metrics/$genome/$sample/"
done

echo
if [[ "$DRYRUN" -eq 1 ]]; then
    echo "DRY RUN: would deliver ${#SAMPLE_DIRS[@]} samples to $DEST; nothing was written there"
else
    echo "Delivered ${#SAMPLE_DIRS[@]} samples to $DEST"
fi
echo
