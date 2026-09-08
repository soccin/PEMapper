# PEMapper

## BRANCH: juno (2026-09-07)

Terminal version of the JUNO branch. This is the last version of PEMapper
to be run on the old JUNO cluster.

## BRANCH: neo (2024-04-18)

Version to work on JUNO (Neo era)

## CHANGES

- local cutadapt in venv, need to install, run `mkVenv` in bin folder

- MAJOR CHANGE: `bwa -M` now on by default

- `runPEMapperMultiDirectories.sh` now limits number of bsubs

- Also uses new picard with a local JAR file

