#!/bin/bash
SDIR="$( cd "$( dirname "$0" )" && pwd )"

if [ ! -e $SDIR/bin/venv/bin/activate ]; then
    echo -e "\n   Need to install venv"
    echo -e "   Run \`mkVenv\` in bin folder\n"
    exit 1
fi


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
    while [ $NUMJOBS -gt 2000 ]; do
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
