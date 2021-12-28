# PEMapper

## dev/wgs_robust

Try to deal with file system issues on JUNO. Ie previous output file not _ready_ for next stage in pipeline. Have `stage_(n-1)` compute and MD5 and then have `stage_(n)` check it.

- Now using system cutadapt

- Also uses new picard with a local JAR file

