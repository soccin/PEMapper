# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

PEMapper is a paired-end FASTQ -> BAM mapping pipeline written entirely in
bash. It submits every step as a separate cluster job and wires the steps
together with job dependencies. There is no build, no test suite, and no
linter; "running" the pipeline is the only way to exercise it.

## Which branch is this? Check before anything else

Branches get switched often in this repo, and this file is **untracked**:
it stays in the working tree across every checkout, so it does not
necessarily describe the code sitting next to it. Never infer the state
of the tree from this file. Two commands orient you:

```bash
git branch --show-current
sed -n 11p pipe.sh
```

Line 11 of `pipe.sh` is the discriminator, and it beats the branch name
because it is the code:

| `pipe.sh:11` | Means |
|---|---|
| `source $SDIR/bin/slurm.sh` | the IRIS / Slurm 25.11.5 line -- `iris`, `devs/slurm-sh`, topic branches cut from them. **This file describes that work.** |
| `source $SDIR/bin/lsf.sh` | JUNO / LSF 10.1 -- `master`, `neo`, `lilac`, `jurassic`, `triassic` and every `flavor/*`. Most of this file does not apply. |

`bin/slurm.sh` and `bin/checkRun.sh` exist only on the Slurm branches, so
their absence says the same thing. The Slurm work was ported from `neo`;
`bin/lsf.sh` is kept on the Slurm branches as reference and is **not**
sourced there.

Where this file and the code disagree, the code is right and the prose is
stale -- say so rather than working from the prose. See "Branch model"
for what else changes under a checkout.

`IRIS_PUNCH_LIST.md` (untracked, repo root) is the plan of record for the
Slurm port and is equally branch-blind: section 0 is the verified cluster
environment, section 1 is everything still open, and the appendix holds
the finished work (A.7 the verification runs, A.8 the genome configs, A.9
the run status reporting). The old `FIX_NOW_260901.md` and
`ROUGH_EDGES_260901.md` are absorbed into A.5 and no longer exist. Read
the punch list before re-deriving anything about the cluster.

## Setup

The cutadapt virtualenv is gitignored and must exist before either entry
point will run (both check for `bin/venv/bin/activate` and abort):

```bash
./00.SETUP.sh          # or: cd bin && . mkVenv
```

`bin/jar/picard.jar` is committed to the repo (~18 MB); no download needed.

## Running

Single sample (one or more FASTQ directories):

```bash
./pipe.sh [-s SAMPLENAME] [-t TAG] [-b BWAFLAG] GENOME SAMPLEDIR [SAMPLEDIR ...]
./pipe.sh -g                     # list genomes in lib/genomes
```

- `SAMPLENAME` defaults to `basename SAMPLEDIR`.
- `-b X` appends `-X` to `BWA_OPTS` (which starts as `-M`).
- Multiple sample dirs may be passed as separate args or `;`-separated.

Batch over a mapping file:

```bash
./runPEMapperMultiDirectories.sh [-t TAG] GENOME MAPPING_FILE
```

The mapping file is tab-delimited; column 2 is the sample name and column 4
is the FASTQ directory. One `pipe.sh` invocation per distinct sample, with
all that sample's directories passed at once. The loop throttles itself
while `squeue -h -u $USER` reports more than 2000 jobs.

Run from the directory where you want output: `pipe.sh` writes `out___*/`
and `SLURM.PEMAP/` relative to the current working directory. `SCRATCH`
is **not** in the working directory any more; see "Data flow".

## Did the run work?

This is the question Slurm makes hard, so it has real machinery behind it.
LSF appended an epilogue to every job log, so grepping the log tree
answered it. Slurm writes **nothing** of its own into the `-o` file: a job
that OOMs, times out or exits non-zero leaves a log that can look
identical to a good one.

```bash
cat out___M/<sample>/RUNSTATUS.txt        # written automatically by __08__STATUS
bin/checkRun.sh                           # every run under ./SLURM.PEMAP
bin/checkRun.sh SLURM.PEMAP/<rundir>      # one run
grep -L "PEMAP STATUS: OK" out___*/*/RUNSTATUS.txt    # a whole batch
grep -L "#PEMAP_EXIT=0" SLURM.PEMAP/*/*.out           # the LSF-style log grep
```

`bin/checkRun.sh` exits 0 (all ok), 1 (failed) and 2 (still running), so it
can gate a downstream script.

Three records make this work, and each covers the others' blind spots.
Do not remove one thinking another subsumes it:

- **`$PEMAP_RUNDIR/jobs.tsv`** -- every job id `QRUN` submitted. Slurm has
  no `post_done(GLOB)` equivalent, so without a recorded id list there is
  no way to ask about "this run's jobs" after the fact.
- **`sacct`** -- the authority, and the only source that sees a job the
  scheduler killed outright. Match on **`State`**, never `ExitCode`: an OOM
  kill reports `State=OUT_OF_MEMORY` with `ExitCode=0:125` while the script
  really exited 137. Anything not `COMPLETED` is a failure.
- **`#PEMAP_EXIT=<rc>`** -- a trailer `QRUN` appends to every job log. It
  survives `sacct` purge and restores the grep workflow. An **absent**
  trailer is itself a failure signal: a walltime kill leaves a log with
  only Slurm's cancellation notice.

`RUNINFO` also carries `SUBMIT_COMPLETE=yes`, written last by `pipe.sh`.
A failed `sbatch` exits all of `pipe.sh`, leaving the jobs already
submitted to run on and the rest never queued; every one of them can
succeed, so without that marker a truncated run reports OK.

## Architecture

### QRUN: the scheduler abstraction

`pipe.sh` sources `bin/slurm.sh`, which defines the `QRUN` shell function.
Every pipeline step is a `QRUN` call. The argument grammar is positional
keywords in a fixed order:

```
QRUN ALLOC JOBTAG [HOLD|HOLDANY "jobid list"] [VMEM total_gb] [SHORT|MEDIUM|LONG] command args...
```

The hold, `VMEM` and the time class are each optional but must appear in
that order if present. Anything after them is the command. Shell
metacharacters in the command must be escaped (`\>\>` for redirection) so
they survive to the compute node; `sbatch --wrap` re-interprets them
under `/bin/sh`.

- `ALLOC` becomes `-N 1 -n 1 -c $ALLOC`. A bare Slurm `-n` means *tasks*
  and would run the command N times.
- `HOLD` takes one argument holding a whitespace-, comma- or
  colon-separated list of **numeric job ids** -- quote it when it can hold
  more than one. It becomes `--dependency=afterok:... --kill-on-invalid-dep=yes`.
  The kill flag is required: `kill_invalid_depend` is off cluster-wide, so
  an orphaned job otherwise pends forever in `DependencyNeverSatisfied`.
- `HOLDANY` is `afterany` with **no** kill flag, so the job runs whatever
  happened upstream. It exists for `__08__STATUS`, which has to run
  precisely when something failed.
- `VMEM` is total memory and is **not** divided by `ALLOC` the way the LSF
  `rusage[mem=]` request had to be. Under `CR_CPU_MEMORY` it is a hard
  cgroup cap, so a request that "worked" on JUNO can be OOM-killed here.
- Time class defaults to `MEDIUM`. `SHORT` -> `cpushort` (`-t 1:55:00`),
  `MEDIUM` -> `cmobic_short` (`-t 2:55:00`), `LONG` -> `cmobic_cpu`
  (`-t 3-00:00:00`). All three are overridable with `PEMAP_PARTITION_*`
  and `PEMAP_TIME_*`; `PEMAP_TIME_OVERRIDE` replaces the walltime for
  every job. `EnforcePartLimits=ALL`, so an over-limit job is rejected at
  submit, not queued.
- `QRUN` sets the global `JOBID` on return and appends it to
  `PEMAP_ALL_IDS`.

`bin/sge.sh` is the legacy SGE implementation of the same contract and
`bin/lsf.sh` the LSF one; both are reference only, neither is sourced.

### Job ids are the dependency graph

Under LSF the graph was job *names* plus `-w post_done(GLOB)`. Slurm has
no name-glob dependency, so every call site captures `$JOBID` at submit
time and threads it forward explicitly:

- `CLIP_ID` -> `BWA_ID` -> `MAP_IDS` (one chain per FASTQ pair)
- `MERGE_ID` holds on `"$MAP_IDS"` (the MAP_03 ids only -- the old
  `${TAG}_MAP_*` glob over-waited on clip and bwa as well)
- `ASTAT_ID`, `INS_ID`, `MD_ID` hold on `$MERGE_ID`
- `__06__POST` holds on `$ASTAT_ID` alone; it only consumes `___AS.txt`,
  and the old `${TAG}__05__STATS*` glob also caught the InsertSize job
- `__07b_CLEANUP` holds on `$MD_ID`
- `__08__STATUS` holds `HOLDANY` on `$PEMAP_ALL_IDS`

Job names are therefore only for `squeue` legibility, **with one
exception**: `bin/checkRun.sh` matches `__08__STATUS` by name to keep the
status job out of the run's own totals. Renaming that job silently breaks
the report.

### Data flow

Per FASTQ pair, in `$SCRATCH`:

1. `find -L` locates R1 files; R2 is derived by replacing the trailing
   `_R1_<digits>.fastq.gz` (only the suffix, to avoid mangling sample names
   that contain `R1_`). A missing R2 is fatal.
2. Read length is sniffed with `bin/getReadLength.py` and `MINLENGTH` is set
   to half of it unless already exported. An empty result is now fatal
   rather than silently falling back to 35.
3. `bin/clipAdapters.sh` runs cutadapt from the venv (TruSeq adapter
   `AGATCGGAAGAGC`, `-O 10 -q 3`).
4. `bwa mem $BWA_OPTS` appends to a SAM that was pre-seeded with an `@PG`
   line carrying `git describe` output and the full command line.
5. picard `AddOrReplaceReadGroups` -> per-pair coordinate-sorted BAM.

Then per sample: `MergeSamFiles` -> `CollectAlignmentSummaryMetrics`,
`CollectInsertSizeMetrics`, `MarkDuplicates` -> `transposeASMetrics.sh` ->
`__08__STATUS`.

`SCRATCH` is `${PEMAP_SCRATCH_ROOT}/<DTS>/$(uuidgen -t)`, defaulting to
`/scratch/core001/bic/$USER/PEMapper`. It must be on a shared filesystem
because it holds the inter-job intermediates. It also holds `RUNLOG` with
the resolved parameters. The `07a` job that removed it is **commented out
in `pipe.sh`** for the duration of the port, per the user -- do not
re-enable it. The `07b` job that removes the pre-MD BAM/BAI is active.

Output goes to `out___<BWATAG>[__NoClip]/<SAMPLENAME>/`, where `BWATAG` is
`BWA_OPTS` with dashes stripped and spaces turned into underscores (so the
default `-M` yields `out___M`). Products are `<S>___MD.bam`, `___MD.txt`,
`___AS.txt`, `___ASt.txt` (transposed), `___INS.txt`, `___INSHist.pdf`,
plus `RUNSTATUS.txt`.

### Run artifacts

`pipe.sh` exports `PEMAP_RUNDIR=$(pwd)/SLURM.PEMAP/<DTS>_<PID>_<SAMPLE>`
before the first `QRUN`. One directory per run, holding:

| File | Written by | What |
|---|---|---|
| `<jobid>.out` | Slurm `-o` | job stdout+stderr, ending in `#PEMAP_EXIT=<rc>` |
| `<jobid>.cmd` | `QRUN` | the resolved `sbatch` line; `--wrap` leaves no script artifact |
| `jobs.tsv` | `QRUN` | `JOBID<TAB>JOBNAME<TAB>LOG`, one line per submitted job |
| `RUNINFO` | `pipe.sh` | sample, tag, genome, version, scratch, cwd, command line, `OUTDIR`, `SUBMIT_COMPLETE` |

The old layout recomputed `SLURM.PEMAP/$D2/$D1/$$` from a fresh timestamp
on **every** `QRUN` call, so one run's logs scattered across several
directories and a run could not be read, or checked, as a unit. If you
add a `QRUN` call site, nothing extra is needed -- the manifest and the
`PEMAP_ALL_IDS` accumulation are inside `QRUN`.

### Genome configs

`lib/genomes/<name>` are shell fragments that get `source`d. They must set
`GENOME_FASTA` and `GENOME_BWA` (optionally `DBSNP`). `pipe.sh` accepts
either a name under `lib/genomes` or a path to any such file, so a one-off
genome does not need to be committed -- which is also how the port's
negative test forces a `bwa` failure.

The IRIS reference tree is `/data1/core001/rsrc/genomic/bic/assemblies`.
Three configs are repointed and live as of 2026-09-02 (commits `169ec88`,
`550b963`, `d02c9a5`); each was verified on disk to have a FASTA, a picard
`.dict` and a **bwa 0.7.19** index, matching the installed binary:

| Config | Reference |
|---|---|
| `human_b37` | `H.sapiens/b37/b37.fasta` |
| `mouse_mm10` | `M.musculus/mm10/mm10.fasta` |
| `human_hg38+mm39` | `hybrids/H.sapiens_M.musculus/hg38_mm39/hg38_mm39.fasta` |

There is no human-only hg38 config: `H.sapiens/hg38` has a FASTA and a
`.dict` but no bwa index.

Two archive directories sit alongside the live configs and **neither holds
anything runnable**:

- `lib/genomes/IRIS/` -- `human_b37+mm10`, `human_GRCh38`, `mouse_GRCm38`.
  The name means "still waiting to be repointed at IRIS", not "works on
  IRIS"; all three carry retired `/juno` and `/rtsess01` paths. They were
  kept as the starting point for a future repoint. `mouse_GRCm38` is
  effectively dead -- GRCm38 is not in the IRIS tree at all,
  `M.musculus/GRCm39` replaced it.
- `lib/genomes/JUNO/` -- the older, much larger set, also on dead
  `/juno/depot` paths.

`pipe.sh -g` is `ls -1 $SDIR/lib/genomes`, so it lists both archive
directories as though they were genomes.

New reference FASTAs need a picard `.dict` built with
`CreateSequenceDictionary` or the metrics steps fail with an obscure
`NullPointerException` in `ReferenceSequenceFileWalker`.

### picard wrappers

`bin/picard.local` and `bin/picardV2` both run `bin/jar/picard.jar` with
`VALIDATION_STRINGENCY=SILENT` and `-Xmx23g`; `picardV2` adds GC thread
limits and an `LSF` first-argument mode that self-submits and is dead on
IRIS. Both use `TMP_DIR=${PEMAP_TMPDIR:-/localscratch/$USER}` and **abort
if that directory cannot be created**. `/localscratch` is node-local disk
and is where picard spills tens of GB of sort; do not add a `/tmp`
fallback, and do not put it on a shared filesystem.

The `-Xmx23g` is hardcoded and does not track what `QRUN` requested, so
the two can drift silently. `VMEM 32` against `-Xmx23g` is the current
margin: `--mem` is a hard cap here, so JVM overhead on top of the heap
would OOM at `VMEM 26`.

### Exit status hygiene

`sacct` and the log trailer both report what the job script returned, so a
wrapper that swallows its payload's status makes every layer above it lie.
Two did, and both were fixed:

- `bin/clipAdapters.sh` ended on `deactivate` (and a bare `wait`, which is
  always 0), so a cutadapt failure produced an empty CLIP fastq and a
  COMPLETED job.
- `bin/transposeASMetrics.sh` was an unguarded pipeline, so a missing
  `___AS.txt` exited 0. It now runs under `pipefail` and checks its input.

Any new wrapper must end on its payload, or capture and re-exit the
status. This class of bug was equally broken under LSF.

## Environment knobs

Read from the environment, not from flags:

- `NO_CLIP=Yes` -- skip cutadapt entirely (just decompresses) and append
  `__NoClip` to the output directory name.
- `MINLENGTH` -- cutadapt `-m`; defaults to half the read length via
  `pipe.sh`, or 35 if `clipAdapters.sh` is run standalone.
- `ERROR` -- cutadapt `-e`; defaults to 0.1.
- `PEMAP_SCRATCH_ROOT` -- parent of `$SCRATCH`; defaults to
  `/scratch/core001/bic/$USER/PEMapper`. `pipe.sh` aborts if it cannot
  create the directory rather than running on with no scratch.
- `PEMAP_TMPDIR` -- picard `TMP_DIR`; defaults to `/localscratch/$USER`.
- `PEMAP_ACCOUNT` -- Slurm account; defaults to `core001`. The default
  partition `cpu` denies `core001`, so `-p` is always explicit.
- `PEMAP_PARTITION_SHORT` / `_MEDIUM` / `_LONG`, `PEMAP_TIME_SHORT` /
  `_MEDIUM` / `_LONG`, `PEMAP_TIME_OVERRIDE`.
- `PEMAP_RUNDIR` -- log and manifest directory; `pipe.sh` sets it.
- `PEMAP_DRYRUN` -- non-empty: print the `sbatch` lines, submit nothing,
  hand back fake ids from 1000001. `RUNINFO` records `DRYRUN=yes` and
  `checkRun.sh` skips such runs rather than reporting them.

## Branch model

Pipeline variants live as long-lived branches rather than options: see
`flavor/wgs_qc*`, `flavor/wes-2024`, `flavor/sgRNA-PE`, `flavor/bwa-aln`,
`flavor/scCNV`, `flavor/SRABams`, `flavor/strandStats`, plus cluster-era
branches (`neo`, `lilac`, `jurassic`, `triassic`, `iris`). Before adding a
mode flag, check whether the behavior already exists on a flavor branch.

### Switching branches

Switching is routine here and the tree takes it fine, but four things
follow from it:

- **`bin/bwa` is a committed symlink whose target is per-branch.** On the
  Slurm branches it points at
  `/usersoftware/core001/common/RHEL_8/bwa/v0.7.19/bin/bwa`; on `master`,
  `neo` and the `flavor/*` branches it still points at
  `/opt/common/CentOS_7/bwa/bwa-0.7.17/bwa`, which does not exist on IRIS.
  Bash skips a broken symlink during `PATH` lookup, so on those branches
  `bwa` silently resolves to whatever is next on `PATH` rather than
  failing. Only `pipe.sh` on the Slurm branches aborts on an empty
  `BWA_VERSION`.
- **Do not switch while a run's jobs are still queued.** `sbatch --wrap`
  stores the command line, not the scripts -- `clipAdapters.sh`,
  `picard.local` and the rest are read from `$SDIR/bin` when each job
  finally executes, so a checkout mid-run swaps the code out from under
  jobs that have not started yet. `bin/checkRun.sh` exits 2 while a run is
  still going; use it before switching.
- **Setup survives a switch.** `bin/venv` is ignored by `bin/.gitignore`
  on every branch and `bin/jar/picard.jar` is committed on every branch,
  so neither needs rebuilding after a checkout.
- **`CLAUDE.md` and `IRIS_PUNCH_LIST.md` are untracked, not ignored**, so
  they appear in `git status` on every branch. That is deliberate: they
  are notes that follow the working tree rather than the history. Do not
  `git add` them by reflex and do not `git clean` them away.

`git describe` runs against `$SDIR/.git` at submit time, so whichever
branch is checked out when a run starts is what lands in the BAM `@PG`
`VN:` field.

Releases are tagged `v_<major>.<minor>.<patch>` (currently `v_4.0.0`).
`pipe.sh` runs `git describe` against its own `$SDIR/.git`, so the checkout
must remain a git working tree -- the version string is stamped into every
BAM's `@PG` record.

## Known rough edges

- The FASTQ `find` pattern accepts `*[_.]R1[_.]*` but the R1->R2 rename
  `case` only handles `_R1_`; the `.R1.` branch is commented out, so
  dot-separated FASTQ names are discovered and then hit the fatal
  "INVALID FASTQ1 filename" path.
- `bin/bwa` is a symlink to
  `/usersoftware/core001/common/RHEL_8/bwa/v0.7.19/bin/bwa` on the Slurm
  branches (the target differs per branch -- see "Switching branches"),
  which is what pins the bwa version -- `pipe.sh` puts `$SDIR/bin` first on `PATH`. Bash
  skips a broken symlink during lookup, so if that path ever goes away
  `bwa` resolves to whatever is next on `PATH` instead of failing; the
  empty-`BWA_VERSION` abort in `pipe.sh` is there to catch that.
- `SAMPLEDIRS` is absolutized before use, so `BASE1` (the FASTQ path with
  `/` turned into `_`) is always the full path. That keeps the scratch
  intermediates out of dotfile territory but makes their names long -- a
  deep enough source tree can approach the 255-byte filename limit.
- `doRNAQC.sh` is a standalone helper, not part of `pipe.sh`, and still
  points at retired `/ifs/work` refFlat paths and `~/Code/Gist`.
- Dead on IRIS but still in the tree: `bin/bsub.sh` (hardcodes the JUNO
  LSF binary), `bin/lsf.sh`, `bin/sge.sh`, `bin/sgeWrap.sh`,
  `bin/cutadapt.off`, `bin/runBwa.sh` (a no-op stub), and the `LSF`
  self-submit branch of `bin/picardV2`.
