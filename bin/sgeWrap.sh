#!/bin/bash
#
# Set shell for job
#$ -S /bin/bash
#
# Execute job from current working directory
#$ -cwd
#
# merge std error and std out into one file
### Don't Merge $ -j y
#

if [ -f ~/.bashrc ] ; then
    . ~/.bashrc
fi

echo "#SGE_WRAP#HOST", `hostname`
echo "#SGE_WRAP#CMD:>" $*
echo "#SGE_WRAP#" `date`
eval $*
echo "#SGE_WRAP#" `date`
