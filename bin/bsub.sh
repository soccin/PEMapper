#!/bin/bash

#echo bsub -R "select[hname!=lt06]" $*

/admin/lsfjuno/lsf/10.1/linux3.10-glibc2.17-x86_64/bin/bsub $@
