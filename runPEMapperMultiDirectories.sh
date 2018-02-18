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
    echo $sample;
    cat $MAPPING | awk -v S=$sample '$2==S{print $4}' \
        | xargs $SDIR/pipe.sh -t $TAG -s $sample $GENOME
done
