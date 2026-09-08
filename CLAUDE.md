# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

PEMapper is a paired-end FASTQ -> BAM mapping pipeline written entirely in
bash. It submits every step as a separate cluster job and wires the steps
together with job dependencies. There is no build, no test suite, and no
linter; "running" the pipeline is the only way to exercise it.

## Which branch is this? Check before anything else

Branches get switched often in this repo, and this file is **tracked on
the Slurm branches only** (added by `983974a` on `iris`). On those
branches it is a normal versioned file; on any branch cut before that
commit -- `master`, `neo`, `devs/slurm-sh`, the `flavor/*` branches -- it
does not exist in the history at all, so a checkout **deletes it from the
working tree**. Either way it does not necessarily describe the code
sitting next to it. Never infer the state of the tree from this file.
Two commands orient you:

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
the LSF and SGE implementations are kept as reference but were moved to
**`bin/attic/`** (commit `7704c7a`) and are **not** sourced. Note the
discriminator above still reads `source $SDIR/bin/lsf.sh` for the LSF
branches -- on those branches the file really is at `bin/lsf.sh`; only the
Slurm branches have `bin/attic`.

Where this file and the code disagree, the code is right and the prose is
stale -- say so rather than working from the prose. See "Branch model"
for what else changes under a checkout.

Five documents sit beside this one, all tracked:

| File | Holds |
|---|---|
| `ISSUES.md` | open work, as a numbered issue list, plus the decisions closed as by-design |
| `CHANGELOG.md` | what changed, per release; `v_4.1.0` in detail, earlier tags one line each |
| `VERSIONS.md` | version numbers only -- the release, and the bwa, picard, Java, Python, cutadapt, R and reference versions a run uses |
| `docs/IRIS_CLUSTER_INFO.md` | measured cluster facts, `sacct` probes with job ids, validation runs |
| `docs/LSF_SLURM_PORT.md` | how the JUNO/LSF -> IRIS/Slurm port was done, and the flag translation table |

Read `docs/IRIS_CLUSTER_INFO.md` before re-deriving anything about the
cluster. The older `IRIS_PUNCH_LIST.md`, `FIX_NOW_260901.md` and
`ROUGH_EDGES_260901.md` are superseded by these.

`CHANGELOG.md` and `VERSIONS.md` were added for the `v_4.1.0` release, on
`rel/v_4.1.0`. They divide the work this file used to carry alone:
anything with a version number on it -- what changed when, which bwa or
picard a run used -- belongs in one of those two, not here. This file
stays about how the code is put together and why.

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
cat out___M/<genome>/<sample>/RUNSTATUS.txt   # written automatically by __08__STATUS
bin/checkRun.sh                           # every run under ./SLURM.PEMAP
bin/checkRun.sh SLURM.PEMAP/<rundir>      # one run
grep -L "PEMAP STATUS: OK" out___*/*/*/RUNSTATUS.txt  # a whole batch
grep -L "#PEMAP_EXIT=0" SLURM.PEMAP/*/*.out           # the LSF-style log grep
```

`bin/checkRun.sh` exits 0 (all ok), 1 (failed) and 2 (still running), so it
can gate a downstream script. Three behaviours of it are deliberate:

- The `__08__STATUS` job **exits non-zero when the run failed**, so it shows
  as `FAILED` in `sacct` -- the exit status carries the verdict, and
  `sacct -j <status id>` answers the question by itself. `checkRun.sh` never
  counts `__08__STATUS` in a run's totals, so this does not double-report.
- `--kill-on-invalid-dep=yes` cancels the whole downstream graph on one
  failure, so most of a report is cascade. Root failures print first, with
  the rest grouped under "cancelled downstream".
- It prefers the log sitting in the run directory it was handed and falls
  back to the absolute path in the manifest, so a run directory can be
  copied elsewhere and still be checked.

To inspect a graph *before* it runs, `squeue -u $USER -o "%.12i %.45j %.10T
%.20E"` -- the `%E` column shows the resolved dependency and is the fastest
way to catch a mis-threaded id.

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
  submit, not queued. `bwa mem` and the picard sort/merge/MD steps are
  `LONG` because they can exceed 3h on a full WGS lane; `cutadapt` is
  `MEDIUM`; transpose and `rm -rf` are `SHORT`.
- `QRUN` sets the global `JOBID` on return and appends it to
  `PEMAP_ALL_IDS`.

`bin/attic/sge.sh` is the legacy SGE implementation of the same contract
and `bin/attic/lsf.sh` the LSF one; both are reference only, neither is
sourced. They are in `bin/attic` rather than `bin` precisely so they are
off `PATH` -- `pipe.sh` puts `$SDIR/bin` first.

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

1. `find -L` locates R1 files with `*[_.]R1[_.]*.fastq.gz`. R2 is derived by
   stripping an anchored suffix tag and appending its R2 form: `_R1_<digits>`
   for underscore names, the **rightmost** `.R1.` before `.fastq.gz` for
   dot-separated ones. Anchoring at the suffix is what keeps a sample name or
   parent directory containing `R1` from being rewritten. A name that matches
   the `find` pattern but neither anchor is fatal -- without that check the
   strip is a no-op and R2 comes back equal to R1. A missing R2 is fatal.
   The read-group `PU` is the filename with that same tag stripped.
2. Read length is sniffed with `bin/getReadLength.py` and `MINLENGTH` is set
   to half of it, **per pair**, unless it came in from the environment --
   `pipe.sh` saves that in `MINLENGTH_ENV` before the loop precisely
   because it exports `MINLENGTH` inside it, and testing the exported
   variable made pair 1's read length apply to every later pair. An empty
   sniff is fatal rather than a silent fallback to 35.
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

Output goes to `out___<BWATAG>[__NoClip]/<GENOME_NAME>/<SAMPLENAME>/`, where
`BWATAG` is `BWA_OPTS` with dashes stripped and spaces turned into underscores
(so the default `-M` yields `out___M`) and `GENOME_NAME` is `basename $GENOME`,
so the same sample mapped against two references does not collide. A path to a
one-off config puts the *filename* there, not a catalog name. Products are
`<S>___MD.bam`, `___MD.txt`, `___AS.txt`, `___ASt.txt` (transposed),
`___INS.txt`, `___INSHist.pdf`, plus `RUNSTATUS.txt`.

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

`pipe.sh -g` and the "Not Defined" fallback both call `listGenomes`
(`pipe.sh:36`), which is `find -L ... -maxdepth 1 -type f`, so the two
archive directories are not listed as genomes. The genome lookup itself
tests `-f`, not `-e`, so naming an archive directory gives the "Not
Defined" message instead of trying to `source` a directory.

New reference FASTAs need a picard `.dict` built with
`CreateSequenceDictionary` or the metrics steps fail with an obscure
`NullPointerException` in `ReferenceSequenceFileWalker`.

### picard wrappers

`bin/picard.local` and `bin/picardV2` both run `bin/jar/picard.jar` with
`VALIDATION_STRINGENCY=SILENT`. `picardV2` used to take an `LSF`
first-argument mode that self-submitted with `bsub`; that branch was
removed 2026-09-07, so the two wrappers are now identical apart from
whitespace. Both are called from `pipe.sh` (`picard.local` for
AddOrReplaceReadGroups and MergeSamFiles, `picardV2` for
CollectInsertSizeMetrics and MarkDuplicates), so neither can be deleted
without editing those call sites. Both use
`TMP_DIR=${PEMAP_TMPDIR:-/localscratch/$USER}` and **abort if that
directory cannot be created**. `/localscratch` is node-local disk and is
where picard spills tens of GB of sort; do not add a `/tmp` fallback, and
do not put it on a shared filesystem.

Both source **`bin/picardJvm.sh`** for the heap and the GC caps. It is one
fragment rather than two copies precisely because the old hardcoded
`-Xmx23g` in each file could drift from what `QRUN` asked for:

- The heap is `$SLURM_MEM_PER_NODE` (MB, always set -- `QRUN` submits with
  `--mem`) minus a **fixed** `PEMAP_JVM_HEADROOM_MB`, default 9216. Fixed,
  not proportional, so `VMEM 32` still gives exactly `-Xmx23g`. Unset, as
  in `doRNAQC.sh`, falls back to 23g; below a 2048m floor it aborts. The
  headroom covers JVM overhead **and** the page cache picard's own writes
  charge to the same cgroup. Do not let Java size the heap itself -- alone
  it takes 25% of the cap.
- `PEMAP_JVM_GC_OPTS` is `-XX:ParallelGCThreads=2 -XX:ConcGCThreads=2`, a
  **static cap, deliberately**. Java 23 derives the same 2 from the cgroup
  on IRIS, so these look redundant; do not remove them and do not derive
  them from `SLURM_CPUS_PER_TASK`. Enough picard JVMs on one node with
  their GCs sized to the physical core count will bury it, and a static cap
  holds whatever the JVM reads. Every picard `QRUN` call site asks `-c 2`.

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
- `PEMAP_JVM_HEADROOM_MB` -- MB held back from `$SLURM_MEM_PER_NODE` when
  `bin/picardJvm.sh` derives the picard heap; defaults to 9216.
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

Switching is routine here and the tree takes it fine, but several things
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
- **`bin/attic/` exists only on the Slurm branches.** Checking out
  `master`, `neo` or a `flavor/*` puts `bsub.sh`, `lsf.sh`, `sge.sh`,
  `sgeWrap.sh`, `cutadapt.off` and `runBwa.sh` back at `bin/` -- where
  those branches need the first four, since
  `pipe.sh:11` there sources `bin/lsf.sh`. A path under `bin/attic` is
  therefore not a stable reference across a checkout.
- **`ISSUES.md`, `CHANGELOG.md`, `VERSIONS.md` and `docs/*.md` are tracked
  on the Slurm branches only**, like this file, so a checkout of `master`,
  `neo` or a `flavor/*` removes them from the working tree.
  `IRIS_PUNCH_LIST.md`, if it is still around,
  is untracked and therefore survives every checkout -- it is superseded,
  but do not `git clean` it away without checking it has nothing left that
  the tracked documents do not.
- **`CLAUDE.md` is tracked, but only on the Slurm branches.** Edits to it
  show up as ` M`, not `??`, and belong in a commit like any other file.
  Checking out a branch that predates `983974a` removes it; `git stash`
  it first, or copy it aside, if you want it to survive the switch.

`git describe` runs against `$SDIR/.git` at submit time, so whichever
branch is checked out when a run starts is what lands in the BAM `@PG`
`VN:` field.

Releases are tagged `v_<major>.<minor>.<patch>`. `master` is at `v_4.0.0`
(JUNO/LSF); `v_4.1.0` is the IRIS/Slurm release, prepared on
`rel/v_4.1.0` and merged back to `master`. `v_4.0.1-juno` sits on the
`juno` branch and is not on this line of history.

`pipe.sh` runs `git describe` against its own `$SDIR/.git`, so the checkout
must remain a git working tree -- the version string is stamped into every
BAM's `@PG` record.

## Known rough edges

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
- `doRNAQC.sh` is a standalone helper, not part of `pipe.sh`. It points at
  retired `/ifs/work` refFlat paths, `~/Code/Gist` and `bsub`, so it is
  **disabled at the top of the file**: it prints what needs fixing and
  exits 0 before reaching any of that. Do not remove the guard without
  porting the paths and the two `bsub` calls.
- Dead on IRIS, moved to `bin/attic/` and off `PATH`: `bsub.sh` (hardcodes
  the JUNO LSF binary), `lsf.sh`, `sge.sh`, `sgeWrap.sh`, `cutadapt.off`,
  and `runBwa.sh` (a no-op stub that echoes its own name and arguments).
  The last two went over in a second sweep (`ca53e56`). Nothing in `bin/`
  is unreachable from `pipe.sh` now.
- `bin/picardV2` and `bin/picard.local` are now byte-identical apart from
  two blank lines, since `picardV2`'s `LSF` branch was removed. Collapsing
  them to one wrapper means editing four `pipe.sh` call sites; not done.
