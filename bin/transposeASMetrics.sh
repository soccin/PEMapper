#!/bin/bash

SDIR="$( cd "$( dirname "$0" )" && pwd )"

echo SDIR=$SDIR

cat $1 | egrep -w "(CATEGORY|PAIR)" | $SDIR/transpose.py
