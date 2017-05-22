#!/bin/bash
SDIR="$( cd "$( dirname "$0" )" && pwd )"

if [ "$#" -lt 2 ]; then
    echo "usage runPEMapperMultiDirectories.sh GENOME MAPPING_FILE [-options to pipe.sh]"
    exit
fi

GENOME=$1
MAPPING=$2

shift 2

for sample in $(cat $MAPPING | cut -f2 | sort | uniq); do
    echo $sample;
    cat $MAPPING | awk -v S=$sample '$2==S{print $4}' \
        | xargs $SDIR/pipe.sh $* -s $sample $GENOME
done
