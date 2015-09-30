#!/bin/bash

cat $1 | egrep -w "(CATEGORY|PAIR)" | /home/socci/bin/transpose.py
