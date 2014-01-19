#!/bin/bash
cat *.e* | egrep -v "(M::|^.main|^INFO|Runtime|Elapsed time:|net.sf.picard|Java HotSpot)" | sort | uniq
