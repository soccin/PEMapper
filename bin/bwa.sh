#!/bin/bash

GENOME=$1
F1=$2
F2=$3
OUT=$4
shift 4
ARGS=$*

bwa mem $ARGS $GENOME $F1 $F2 >>$OUT

