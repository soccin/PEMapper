QSYNC=#


##
# QRUN ALLOC QTAG <HOLD hold_id> <VMEM size> LONG
#
# HOLD, VMEM and LONG are optional but if you more than one
# they must be in this order
#   HOLD
#   VMEM
#   LONG
#

QRUN () {

    # Get current Unix timestamp
    TS=$(date +%s)

    # Calculate the modulo and division of timestamp by 100 to
    # create a multi-level directory structure:
    D1=$((TS % 100))
    T2=$((TS / 100))
    D2=$((T2 % 100))
    D3=$((T2 / 100))

    # Create a multi-level directory path for efficient handling
    # of a large number of files/directories.
    # Where PID==$$ is the Process ID, a unique identifier for
    # each running process.
    LSFDIR=LSF.PEMAP/$D2/$D1/$$
    mkdir -p $LSFDIR

    if [ "$LSF_VERSION" == "" ]; then
        export LSF_VERSION=$(echo $LSF_SERVERDIR | perl -ne 'm|/([^/]+)/linux|;print $1')
        echo setting LSF_VERSION="$LSF_VERSION"
    fi

    case $LSF_VERSION in
        10.1)
            TIME_FLAG="-W"
            TIME_SHORT="$TIME_FLAG 59"
            TIME_LONG="$TIME_FLAG 59"

        ;;

        9.1)
            TIME_FLAG=""
            TIME_SHORT=""
            TIME_LONG=""
        ;;

        *)
        echo "Error invalid LSF_VERSION ["${LSF_VERSION}"]"
        exit -1
        ;;

    esac

    ALLOC=$1
    QTAG=$2
    echo QTAG=$QTAG
    shift 2
    QHOLD=""
    if [ "$1" == "HOLD" ]; then
        QHOLD="-w post_done($2)"
        shift 2
        echo QHOLD=$QHOLD
    fi

    VMEM=""
    if [ "$1" == "VMEM" ]; then
        if [ "$LSF_VERSION" == "10.1" ]; then

            TOTALMEM=$2
            MEMPERSLOT=$((TOTALMEM / ALLOC))
            VMEM='-R "rusage[mem='$MEMPERSLOT']"'

        else
            VMEM='-R "rusage[mem='$2']"'
        fi

        shift 2
        echo VMEM=$VMEM
    fi

    TIME=$TIME_SHORT
    if [ "$1" == "LONG" ]; then
        TIME=$TIME_LONG
        shift 1
        echo LONG Job
    fi

    if [ "$LSF_TIME_OVERRIDE" != "" ]; then
        TIME="$TIME_FLAG $LSF_TIME_OVERRIDE"
        echo "Overriding LSF-TIME setting to ${TIME}"
    fi

    HOSTS=""
    if [ "$BHOST_EXC" != "" ]; then
        EXCARG=$(echo $BHOST_EXC | tr ',' '\n' | awk '{print "(hname!="$1")"}' | xargs  | sed 's/ /\&\&/g')
        HOSTS="-R select["$EXCARG"]"
        echo "EXCLUDE="$HOSTS
    fi

    RET=$(bsub -R "fscratch" $TIME $QHOLD $VMEM -n $ALLOC -J $QTAG -o $LSFDIR/ $*)
    echo RET=bsub $HOSTS -R "fscratch" $TIME $QHOLD $VMEM -n $ALLOC -J $QTAG -o $LSFDIR/ $*
    echo "#QRUN RET=" $RET
    echo
    JOBID=$(echo $RET | perl -ne '/Job <(\d+)> /;print $1')

}
