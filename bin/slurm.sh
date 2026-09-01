#
# Slurm backend for PEMapper (IRIS). Analog of bin/lsf.sh.
#
# QRUN ALLOC QTAG [HOLD|HOLDANY "JOBID LIST"] [VMEM total_gb] [SHORT|MEDIUM|LONG] command args...
#
# The hold, VMEM and the time class are all optional but if more than one
# is given they must appear in this order:
#   HOLD | HOLDANY
#   VMEM
#   SHORT|MEDIUM|LONG    (default MEDIUM)
#
# HOLD takes a *single* argument holding a whitespace-, comma- or
# colon-separated list of numeric Slurm job ids, so quote it when it can
# hold more than one:
#
#     QRUN 2 MERGE HOLD "$MAP_IDS" VMEM 32 LONG picard.local MergeSamFiles ...
#
# HOLD is afterok: the job runs only if every id succeeded and is
# cancelled otherwise. HOLDANY is afterany: the job runs once every id
# has reached a terminal state, whatever that state was. HOLDANY exists
# for the __08__STATUS job, which has to run precisely when something
# upstream failed.
#
# Slurm has no equivalent of the LSF `-w post_done(GLOB)` name glob, so
# every call site must capture $JOBID at submit time and thread the ids
# forward explicitly. QRUN sets the global JOBID on return and also
# accumulates every id it has submitted in PEMAP_ALL_IDS.
#
# Every submitted job is recorded in $PEMAP_RUNDIR/jobs.tsv and every job
# log ends with a "#PEMAP_EXIT=<rc>" trailer. Together they are what
# bin/checkRun.sh reads to say whether a run succeeded; slurm, unlike
# LSF, leaves no epilogue in the log to grep for.
#
# Environment knobs:
#   PEMAP_ACCOUNT            slurm account            (default core001)
#   PEMAP_PARTITION_SHORT    partition for SHORT      (default cpushort)
#   PEMAP_PARTITION_MEDIUM   partition for MEDIUM     (default cmobic_short)
#   PEMAP_PARTITION_LONG     partition for LONG       (default cmobic_cpu)
#   PEMAP_TIME_SHORT/_MEDIUM/_LONG   per class walltime
#   PEMAP_TIME_OVERRIDE      walltime for every job, overrides the class
#   PEMAP_RUNDIR             log and manifest directory for this run
#   PEMAP_DRYRUN             non-empty: print the sbatch line, submit nothing
#

SDIR="$( cd "$( dirname "$0" )" && pwd )"

##
# Scrub SLURM_* inherited from an interactive allocation. We submit with
# the default --export=ALL, so a stale SLURM_JOB_ID would otherwise leak
# into every job we start. SLURM_CONF is kept; the client tools need it.

for PEMAP_V in ${!SLURM_@}; do
    if [ "$PEMAP_V" != "SLURM_CONF" ]; then
        unset $PEMAP_V
    fi
done
unset PEMAP_V

PEMAP_ACCOUNT=${PEMAP_ACCOUNT:-core001}

##
# Time class -> partition. The default partition (cpu) denies core001 so
# -p is always explicit. Walltimes stay under the partition MaxTime
# because EnforcePartLimits=ALL rejects an over-limit job at submit time
# rather than queueing it.
#
#   SHORT   cpushort      MaxTime 02:00:00
#   MEDIUM  cmobic_short  MaxTime 03:00:00
#   LONG    cmobic_cpu    MaxTime 7-00:00:00

PEMAP_PARTITION_SHORT=${PEMAP_PARTITION_SHORT:-cpushort}
PEMAP_PARTITION_MEDIUM=${PEMAP_PARTITION_MEDIUM:-cmobic_short}
PEMAP_PARTITION_LONG=${PEMAP_PARTITION_LONG:-cmobic_cpu}

PEMAP_TIME_SHORT=${PEMAP_TIME_SHORT:-1:55:00}
PEMAP_TIME_MEDIUM=${PEMAP_TIME_MEDIUM:-2:55:00}
PEMAP_TIME_LONG=${PEMAP_TIME_LONG:-3-00:00:00}

PEMAP_FAKEID=1000000

# Every job id QRUN has submitted, in submission order. pipe.sh hands
# this to the __08__STATUS job so it can wait on the whole run.
PEMAP_ALL_IDS=""

QRUN () {

    #
    # One directory per run, not per QRUN call. The old timestamp-modulo
    # fan-out was recomputed on every call, so jobs submitted in
    # different seconds landed in different directories and a run's logs
    # could not be read, or checked, as a unit. pipe.sh sets
    # PEMAP_RUNDIR before the first call so the name carries the sample.
    #
    if [ "$PEMAP_RUNDIR" == "" ]; then
        PEMAP_RUNDIR=$(pwd)/SLURM.PEMAP/$(date +%Y%m%d_%H%M%S)_$$
    fi

    if [ ! -e $PEMAP_RUNDIR/jobs.tsv ]; then
        mkdir -p $PEMAP_RUNDIR
        printf '#JOBID\tJOBNAME\tLOG\n' > $PEMAP_RUNDIR/jobs.tsv
    fi

    ALLOC=$1
    QTAG=$2
    echo QTAG=$QTAG
    shift 2

    QHOLD=""
    if [ "$1" == "HOLD" ] || [ "$1" == "HOLDANY" ]; then

        # kill_invalid_depend is not set cluster wide, so without
        # --kill-on-invalid-dep an orphaned afterok job pends forever in
        # DependencyNeverSatisfied.
        DEPTYPE=afterok
        DEPKILL="--kill-on-invalid-dep=yes"

        if [ "$1" == "HOLDANY" ]; then
            # afterany is satisfied by any terminal state, so it cannot
            # be orphaned, and it must not be killed when something
            # upstream fails: reporting that failure is its whole job.
            DEPTYPE=afterany
            DEPKILL=""
        fi

        DEPIDS=""
        for JID in $(echo "$2" | tr ',:' '  '); do
            case "$JID" in
                ''|*[!0-9]*)
                    echo
                    echo "FATAL ERROR [$QTAG]: non-numeric HOLD job id [$JID]"
                    echo "HOLD takes slurm job ids, not job names"
                    echo
                    exit 1
                    ;;
            esac
            DEPIDS=${DEPIDS}:${JID}
        done

        if [ "$DEPIDS" == "" ]; then
            # An empty --dependency=afterok: is a submit error, so drop
            # the flag entirely and say so.
            echo "WARNING [$QTAG]: empty HOLD list; submitting with no dependency"
        else
            QHOLD="--dependency=${DEPTYPE}${DEPIDS} $DEPKILL"
        fi

        shift 2
        echo QHOLD=$QHOLD
    fi

    VMEM=""
    if [ "$1" == "VMEM" ]; then
        # Slurm --mem is the total for the job and is a hard cgroup cap
        # under CR_CPU_MEMORY; do not divide by ALLOC the way the LSF
        # rusage[mem=] request had to be.
        VMEM="--mem=${2}G"
        shift 2
        echo VMEM=$VMEM
    fi

    QCLASS=MEDIUM
    case "$1" in
        SHORT|MEDIUM|LONG)
            QCLASS=$1
            shift 1
            ;;
    esac

    case $QCLASS in
        SHORT)
            PARTITION=$PEMAP_PARTITION_SHORT
            QTIME=$PEMAP_TIME_SHORT
            ;;
        MEDIUM)
            PARTITION=$PEMAP_PARTITION_MEDIUM
            QTIME=$PEMAP_TIME_MEDIUM
            ;;
        LONG)
            PARTITION=$PEMAP_PARTITION_LONG
            QTIME=$PEMAP_TIME_LONG
            ;;
    esac
    echo CLASS=$QCLASS PARTITION=$PARTITION TIME=$QTIME

    if [ "$PEMAP_TIME_OVERRIDE" != "" ]; then
        QTIME=$PEMAP_TIME_OVERRIDE
        echo "Overriding walltime setting to ${QTIME}"
    fi

    # -N 1 -n 1 -c ALLOC: LSF slots are cores; a bare slurm -n would be
    # tasks and would run the command ALLOC times.
    SBATCH_OPTS="-A $PEMAP_ACCOUNT -p $PARTITION -t $QTIME -N 1 -n 1 -c $ALLOC"
    SBATCH_OPTS="$SBATCH_OPTS -J $QTAG -o $PEMAP_RUNDIR/%j.out $VMEM $QHOLD"

    #
    # LSF appended an epilogue to every job log; slurm writes nothing of
    # its own, so a failed job's log can look exactly like a good one.
    # Echo the payload's exit status and then re-exit with it: the log
    # becomes self describing and afterok dependencies still see the real
    # status. A log with no trailer means the job never reached the end
    # of its script -- OOM, walltime, node failure -- which is itself a
    # failure signal, and bin/checkRun.sh reads it as one.
    #
    QWRAP="$* ; PEMAP_RC=\$?; echo \"#PEMAP_EXIT=\$PEMAP_RC [$QTAG]\"; exit \$PEMAP_RC"

    echo "#QRUN CMD= sbatch $SBATCH_OPTS --wrap=\"$QWRAP\""

    if [ "$PEMAP_DRYRUN" != "" ]; then

        PEMAP_FAKEID=$((PEMAP_FAKEID + 1))
        JOBID=$PEMAP_FAKEID
        echo "#QRUN DRYRUN JOBID=" $JOBID

    else

        RET=$($SDIR/bin/sbatch.sh --parsable $SBATCH_OPTS --wrap="$QWRAP")
        RC=$?

        # --parsable prints JOBID or JOBID;CLUSTER
        JOBID=$(echo $RET | cut -d';' -f1)

        if [ "$RC" != "0" ] || [ "$JOBID" == "" ]; then
            echo
            echo "FATAL ERROR [$QTAG]: sbatch failed rc=[$RC] output=[$RET]"
            echo
            exit 1
        fi

        echo "#QRUN JOBID=" $JOBID

        # --wrap leaves no script artifact, so keep the resolved command
        # line next to the job log.
        echo "sbatch $SBATCH_OPTS --wrap=\"$QWRAP\"" > $PEMAP_RUNDIR/${JOBID}.cmd

    fi

    #
    # The manifest is what makes a run checkable after the fact:
    # bin/checkRun.sh asks sacct about exactly these ids. Slurm has no
    # way to find a run's jobs by name pattern the way LSF's
    # post_done(GLOB) could.
    #
    printf '%s\t%s\t%s\n' $JOBID "$QTAG" $PEMAP_RUNDIR/${JOBID}.out \
        >> $PEMAP_RUNDIR/jobs.tsv

    PEMAP_ALL_IDS="$PEMAP_ALL_IDS $JOBID"

    echo

}
