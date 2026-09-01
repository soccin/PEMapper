#
# Slurm backend for PEMapper (IRIS). Analog of bin/lsf.sh.
#
# QRUN ALLOC QTAG [HOLD "JOBID LIST"] [VMEM total_gb] [SHORT|MEDIUM|LONG] command args...
#
# HOLD, VMEM and the time class are all optional but if more than one is
# given they must appear in this order:
#   HOLD
#   VMEM
#   SHORT|MEDIUM|LONG    (default MEDIUM)
#
# HOLD takes a *single* argument holding a whitespace-, comma- or
# colon-separated list of numeric Slurm job ids, so quote it when it can
# hold more than one:
#
#     QRUN 2 MERGE HOLD "$MAP_IDS" VMEM 32 LONG picard.local MergeSamFiles ...
#
# Slurm has no equivalent of the LSF `-w post_done(GLOB)` name glob, so
# every call site must capture $JOBID at submit time and thread the ids
# forward explicitly. QRUN sets the global JOBID on return.
#
# Environment knobs:
#   PEMAP_ACCOUNT            slurm account            (default core001)
#   PEMAP_PARTITION_SHORT    partition for SHORT      (default cpushort)
#   PEMAP_PARTITION_MEDIUM   partition for MEDIUM     (default cmobic_short)
#   PEMAP_PARTITION_LONG     partition for LONG       (default cmobic_cpu)
#   PEMAP_TIME_SHORT/_MEDIUM/_LONG   per class walltime
#   PEMAP_TIME_OVERRIDE      walltime for every job, overrides the class
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

QRUN () {

    # Get current Unix timestamp
    TS=$(date +%s)

    # Calculate the modulo and division of timestamp by 100 to
    # create a multi-level directory structure:
    D1=$((TS % 100))
    T2=$((TS / 100))
    D2=$((T2 % 100))

    # Create a multi-level directory path for efficient handling
    # of a large number of files/directories.
    # Where PID==$$ is the Process ID, a unique identifier for
    # each running process.
    SLURMDIR=SLURM.PEMAP/$D2/$D1/$$
    mkdir -p $SLURMDIR

    ALLOC=$1
    QTAG=$2
    echo QTAG=$QTAG
    shift 2

    QHOLD=""
    if [ "$1" == "HOLD" ]; then

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
            # kill_invalid_depend is not set cluster wide, so without
            # --kill-on-invalid-dep an orphaned job pends forever in
            # DependencyNeverSatisfied.
            QHOLD="--dependency=afterok${DEPIDS} --kill-on-invalid-dep=yes"
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
    SBATCH_OPTS="$SBATCH_OPTS -J $QTAG -o $SLURMDIR/%j.out $VMEM $QHOLD"

    echo "#QRUN CMD= sbatch $SBATCH_OPTS --wrap=\"$*\""

    if [ "$PEMAP_DRYRUN" != "" ]; then
        PEMAP_FAKEID=$((PEMAP_FAKEID + 1))
        JOBID=$PEMAP_FAKEID
        echo "#QRUN DRYRUN JOBID=" $JOBID
        echo
        return
    fi

    RET=$($SDIR/bin/sbatch.sh --parsable $SBATCH_OPTS --wrap="$*")
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

    # --wrap leaves no script artifact, so keep the resolved command line
    # next to the job log.
    echo "sbatch $SBATCH_OPTS --wrap=\"$*\"" > $SLURMDIR/${JOBID}.cmd
    echo

}
