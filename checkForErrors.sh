#!/bin/bash
cat *.e* | egrep -v "(M::|^.main|^INFO|Runtime|Elapsed time:|net.sf.picard.sam|Java HotSpot)" | sort | uniq
