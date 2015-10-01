#!/usr/bin/env python2.7
'''
getReadLength.py

Reads the first 10 sequences from a FASTQ file
(1 line per rec convention) and computes the
max READLEN
'''

import sys

sequences=[]
for i,line in enumerate(sys.stdin):
    if i % 4 == 1:
        sequences.append(line.strip())
        if len(sequences)==10:
            break

print max([len(x) for x in sequences])
