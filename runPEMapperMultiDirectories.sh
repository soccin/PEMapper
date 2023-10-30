#!/bin/bash
SDIR="$( cd "$( dirname "$0" )" && pwd )"

TAG=qPEMAP
while getopts "t:" opt; do
    case $opt in
        t)  TAG=$OPTARG
            ;;
        \?)
            echo "usage runPEMapperMultiDirectories.sh [-t TAG] GENOME MAPPING_FILE"
            exit
            ;;
    esac
done

shift $((OPTIND - 1))

if [ "$#" -ne 2 ]; then
    echo "usage runPEMapperMultiDirectories.sh [-t TAG] GENOME MAPPING_FILE"
    exit
fi

GENOME=$1
MAPPING=$2

for sample in $(cat $MAPPING | cut -f2 | sort | uniq); do

    NUMJOBS=$(bjobs | wc -l);
    while [ $NUMJOBS -gt 1000 ]; do
        date
        echo NUMJOBS=$NUMJOBS;
        NUMJOBS=$(bjobs | wc -l);
        sleep 60;
    done

    echo "========================================"
    echo $sample;
    cat $MAPPING | awk -v S=$sample '$2==S{print $4}' \
        | xargs $SDIR/pipe.sh -t $TAG -s $sample $GENOME
    echo "done with $sample"
    echo "========================================"

done

echo
echo
echo DONE
echo
echo
