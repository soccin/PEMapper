#!/bin/bash
cat *.e* | egrep -v "(^$|M::|^.main|^INFO|Runtime|Elapsed time:|Java HotSpot|^\[)" | sort | uniq
