# PEMapper

Paired-end FASTQ to BAM mapping pipeline. Every step is submitted as a
separate cluster job; the steps are wired together with job dependencies.

## VERSION: v_4.1.0 (2026-09-08)

Runs on IRIS (RHEL 8, Slurm). Ported from `neo`, which targeted JUNO/LSF.
Check what a checkout actually is before trusting the branch name — line
11 of `pipe.sh` is the discriminator:

```bash
sed -n 11p pipe.sh          # source $SDIR/bin/slurm.sh  ->  this version
```

| File | Holds |
|---|---|
| `CHANGELOG.md` | what changed, per release |
| `VERSIONS.md` | what version of everything a run uses |
| `ISSUES.md` | open work |
| `CLAUDE.md` | architecture and internals |
| `docs/` | measured cluster facts, and how the LSF -> Slurm port was done |

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

Set `PEMAP_DRYRUN=1` to print the `sbatch` lines and submit nothing.

## DID IT WORK?

Slurm writes nothing of its own into a job's log, so a job that ran out of
memory, hit the walltime or exited non-zero leaves a log that can look
exactly like a good one. Every run therefore records its job ids, and ends
with a job that writes the verdict next to the results:

```bash
cat out___M/<genome>/<sample>/RUNSTATUS.txt   # written automatically
bin/checkRun.sh                           # every run under ./SLURM.PEMAP
bin/checkRun.sh SLURM.PEMAP/<rundir>      # one run
```

The first line is `PEMAP STATUS: OK`, `FAILED` or `RUNNING`. A failure
names the jobs that failed, their Slurm state and their log paths, with
the root cause first and the cancelled downstream jobs grouped after it.

For a whole batch:

```bash
grep -L "PEMAP STATUS: OK" out___*/*/*/RUNSTATUS.txt
```

`bin/checkRun.sh` exits 0 (all ok), 1 (something failed) or 2 (still
running), so it can gate a downstream script.

## OUTPUT

`out___<BWATAG>[__NoClip]/<GENOME_NAME>/<SAMPLENAME>/`. `BWATAG` is
`BWA_OPTS` with the dashes stripped and spaces turned into underscores, so
the default `-M` gives `out___M`, and `NO_CLIP=Yes` makes that
`out___M__NoClip`. `GENOME_NAME` is `basename` of the genome argument: the
catalog name for `human_b37`, but the *config filename* when a path to a
one-off config is passed, so `/path/to/my_genome.sh` lands under
`my_genome.sh`, not under the reference it names. The default `-M` with `human_b37` therefore gives
`out___M/human_b37/`:

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

## GENOMES

`lib/genomes/<name>` are shell fragments that set `GENOME_FASTA` and
`GENOME_BWA`. A path to any such file works too, so a one-off genome does
not have to be committed. Three are live on the IRIS reference tree:
`human_b37`, `mouse_mm10` and `human_hg38+mm39`. The `IRIS/` and `JUNO/`
subdirectories are archives on retired paths and hold nothing runnable;
`pipe.sh -g` does not list them.

## CHANGES

`CHANGELOG.md`. In short, `v_4.1.0` replaces the LSF backend with Slurm,
threads dependencies as job ids, moves scratch and the picard temp off the
working directory, derives the picard heap from the Slurm allocation, and
adds the run-verification machinery (`bin/checkRun.sh`, `RUNSTATUS.txt`,
the per-run job-id manifest and the `#PEMAP_EXIT=` log trailer). Older
releases, back to `v_0.0.1`, are summarized there too.
