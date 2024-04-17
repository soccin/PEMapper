#!/bin/bash

#
# This stuff is now handled with the
# BSUBRC stuff in the ~/bin/bsub
# script
#
#echo bsub -R "select[hname!=lt06]" $*

bsub $*
