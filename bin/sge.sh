export PATH=/common/sge/bin/lx24-amd64:$PATH
SGE=/home/socci/Work/SGE
QSYNC=$SGE/qSYNC

QUEUES=nce.q,lau.q,mad.q
QRUN () {
    ALLOC=$1
    QTAG=$2
    echo QTAG=$QTAG
    shift 2
    QHOLD=""
    if [ "$1" == "HOLD" ]; then
        QHOLD="-hold_jid $2"
        shift 2
        echo QHOLD=$QHOLD
    fi

    VMEM=""
    if [ "$1" == "VMEM" ]; then
        VMEM="-l virtual_free=$2"
        shift 2
        echo VMEM=$VMEM
    fi

    RET=$(qsub $QHOLD $VMEM -q $QUEUES -pe alloc $ALLOC -N $QTAG -V $SDIR/bin/sgeWrap.sh $*)
    echo "#QRUN RET=" $RET
    echo
    JOBID=$(echo $RET | perl -ne '/Your job (\d+) /;print $1')

}
