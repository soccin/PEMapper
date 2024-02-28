#!/bin/bash

#echo bsub -R "select[hname!=lt06]" $*
bsub -R "select[hname!=lt06]" $*
