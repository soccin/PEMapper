#!/usr/bin/env python3

import sys

data=[]

for line in sys.stdin:
    data.append(line.strip().split("\t"))
for dd in zip(*data):
    print("\t".join(dd))
