QSYNC=#


##
# QRUN ALLOC QTAG <HOLD hold_id> <VMEM size>
#
# HOLD and VMEM are optional but if you use both then
# HOLD MUST COME BEFORE VMEM
#

QRUN () {
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
        VMEM="-R "rusage[mem=$2]"
        shift 2
        echo VMEM=$VMEM
    fi

    RET=$(bsub $QHOLD $VMEM -n $ALLOC -J $QTAG $*)
    echo "#QRUN RET=" $RET
    echo
    JOBID=$(echo $RET | perl -ne '/Job <(\d+)> /;print $1')

}
