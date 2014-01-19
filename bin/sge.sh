export PATH=/common/sge/bin/lx24-amd64:$PATH
SGE=/home/socci/Work/SGE
QSYNC=$SGE/qSYNC

QUEUES=nce.q,lau.q,mad.q
QRUN () {
    ALLOC=$1
    QTAG=$2
    echo QTAG=$QTAG
    shift 2
    RET=$(qsub -q $QUEUES -pe alloc $ALLOC -N $QTAG -V $SDIR/bin/sgeWrap.sh $*)
    echo "#QRUN RET=" $RET
    echo

}