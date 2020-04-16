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

    if [ "$LSF_VERSION" == "" ]; then
        export LSF_VERSION=$(echo $LSF_SERVERDIR | perl -ne 'm|/([^/]+)/linux|;print $1')
        echo setting LSF_VERSION="$LSF_VERSION"
    fi

    case $LSF_VERSION in
        10.1)
            TIME_FLAG="-W"
            TIME_SHORT="$TIME_FLAG 59"
            TIME_LONG="$TIME_FLAG 359"

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

    RET=$(bsub $TIME $QHOLD $VMEM -n $ALLOC -J $QTAG -o LSF.PEMAP/ $*)
    echo RET=bsub $QHOLD $VMEM -n $ALLOC -J $QTAG -o LSF.PEMAP/ $*
    echo "#QRUN RET=" $RET
    echo
    JOBID=$(echo $RET | perl -ne '/Job <(\d+)> /;print $1')

}
