# PEMapper

Paired-end FASTQ to BAM mapping pipeline. Every step is submitted as a
separate cluster job; the steps are wired together with job dependencies.

## BRANCH: iris (2026-09-01)

Version to work on IRIS (Slurm 25.11.5). Ported from `neo`, which
targeted JUNO/LSF.

## SETUP

The cutadapt virtualenv is gitignored and must exist before either entry
point will run:

```bash
./00.SETUP.sh          # or: cd bin && . mkVenv
```

`bin/jar/picard.jar` is committed to the repo; no download needed.

## RUNNING

Run from the directory you want the output in.

One sample, from one or more FASTQ directories:

```bash
./pipe.sh [-s SAMPLENAME] [-t TAG] [-b BWAFLAG] GENOME SAMPLEDIR [SAMPLEDIR ...]
./pipe.sh -g                     # list genomes
```

A set of samples from a tab-delimited mapping file (column 2 is the
sample name, column 4 the FASTQ directory):

```bash
./runPEMapperMultiDirectories.sh [-t TAG] GENOME MAPPING_FILE
```

## DID IT WORK?

Slurm writes nothing of its own into a job's log, so a job that ran out of
memory, hit the walltime or exited non-zero leaves a log that can look
exactly like a good one. Every run therefore records its job ids, and ends
with a job that writes the verdict next to the results:

```bash
cat out___M/<sample>/RUNSTATUS.txt        # written automatically
bin/checkRun.sh                           # every run under ./SLURM.PEMAP
bin/checkRun.sh SLURM.PEMAP/<rundir>      # one run
```

The first line is `PEMAP STATUS: OK`, `FAILED` or `RUNNING`. A failure
names the jobs that failed, their Slurm state and their log paths, with
the root cause first and the cancelled downstream jobs grouped after it.

For a whole batch:

```bash
grep -L "PEMAP STATUS: OK" out___*/*/RUNSTATUS.txt
```

`bin/checkRun.sh` exits 0 (all ok), 1 (something failed) or 2 (still
running), so it can gate a downstream script.

## OUTPUT

`out___<BWA_OPTS>/<SAMPLENAME>/`, so the default `-M` gives `out___M/`:

| File | What |
|---|---|
| `<S>___MD.bam`, `___MD.bai` | duplicate-marked alignments |
| `<S>___MD.txt` | MarkDuplicates metrics |
| `<S>___AS.txt`, `___ASt.txt` | alignment summary metrics, and transposed |
| `<S>___INS.txt`, `___INSHist.pdf` | insert size metrics |
| `RUNSTATUS.txt` | did every job in the run succeed |

Job logs, the resolved `sbatch` lines, the job-id manifest and `RUNINFO`
go to `SLURM.PEMAP/<timestamp>_<pid>_<sample>/`, one directory per run.
Intermediates go to `$PEMAP_SCRATCH_ROOT` on shared scratch, not to the
working directory.

## CHANGES

### IRIS / Slurm (2026-09)

- Slurm backend `bin/slurm.sh` replaces `bin/lsf.sh`, which stays as
  reference. Dependencies are threaded as job ids; Slurm has no
  equivalent of the LSF `-w post_done(GLOB)` name glob.
- `bin/checkRun.sh` plus a per-run job-id manifest, a `#PEMAP_EXIT=`
  trailer on every job log, and an automatic `RUNSTATUS.txt`.
- One log directory per run instead of a timestamp fan-out per job.
- `bin/getReadLength.py` and `bin/transpose.py` ported to Python 3; there
  is no `python2` on IRIS, and both had been failing silently.
- picard spills to `/localscratch/$USER` and aborts if it cannot.
- `runPEMapperMultiDirectories.sh` throttles on `squeue`, not `bjobs`.

Only the `human_b37` genome config has been repointed at IRIS paths so
far; the other four still reference retired `/juno` paths.

### neo (2024-04-18)

- local cutadapt in venv, need to install, run `mkVenv` in bin folder
- MAJOR CHANGE: `bwa -M` now on by default
- `runPEMapperMultiDirectories.sh` no limits number of bsubs
- Also uses new picard with a local JAR file
