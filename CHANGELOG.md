# Changelog

All notable changes to PEMapper. Versions are the release tags
(`v_<major>.<minor>.<patch>`); the string in a BAM's `@PG` `VN:` field is
`git describe` against the checkout that submitted the run.

Tool and reference versions are in `VERSIONS.md`. Open work is in
`ISSUES.md`.

## v_4.1.0 — 2026-09-08

The IRIS / Slurm release. Everything from `v_4.0.0` (JUNO / LSF 10.1) to
here. The pipeline's stages and its output layout are unchanged; the
scheduler, the temp/scratch layout and the run-verification machinery are
not.

### Added

- **Slurm backend `bin/slurm.sh`.** Defines `QRUN` with the same
  positional grammar the LSF backend used —
  `QRUN ALLOC JOBTAG [HOLD|HOLDANY ids] [VMEM gb] [SHORT|MEDIUM|LONG] cmd`.
  `ALLOC` becomes `-c` (a bare Slurm `-n` is *tasks* and would run the
  command N times); `VMEM` is total memory and is no longer divided by the
  core count the way `rusage[mem=]` had to be.
- **Time classes and partitions.** `SHORT` → `cpushort` (1:55:00),
  `MEDIUM` → `cmobic_short` (2:55:00), `LONG` → `cmobic_cpu` (3-00:00:00),
  each overridable. `EnforcePartLimits=ALL` on IRIS, so an over-limit job
  is rejected at submit rather than queued.
- **`HOLDANY`**, an `afterany` dependency with no kill flag, for the
  status job that has to run precisely when something upstream failed.
- **Run verification.** `bin/checkRun.sh` reports one run or every run
  under `./SLURM.PEMAP` and exits 0 (ok) / 1 (failed) / 2 (running), so it
  can gate a downstream script. Root failures print first, cascade
  cancellations grouped after.
- **`RUNSTATUS.txt`**, written next to the results by an automatic
  `__08__STATUS` job. First line is `PEMAP STATUS: OK|FAILED|RUNNING`.
  The job itself exits non-zero on a failed run, so `sacct` alone answers
  the question too.
- **Three independent run records**, each covering the others' blind
  spots: `jobs.tsv` (every submitted job id — Slurm has no
  `post_done(GLOB)` equivalent, so the id list is the only handle on "this
  run's jobs"), `sacct` state (the only source that sees a job the
  scheduler killed outright), and a `#PEMAP_EXIT=<rc>` trailer appended to
  every job log (survives `sacct` purge; an *absent* trailer is itself a
  failure signal).
- **`RUNINFO`**, with sample, tag, genome, version, scratch, cwd, command
  line, `OUTDIR`, and `SUBMIT_COMPLETE=yes` written last. A failed
  `sbatch` exits all of `pipe.sh`; without that marker every job that did
  get queued can succeed and a truncated run reports OK.
- **`bin/picardJvm.sh`**, one sourced fragment for the picard heap and GC
  caps, replacing a hardcoded `-Xmx23g` in each wrapper.
- **`bin/sbatch.sh`**, which `exec`s `/usr/bin/sbatch` directly, past both
  `$SDIR/bin` and any personal `~/bin/sbatch`.
- **`PEMAP_DRYRUN`** — print the resolved `sbatch` lines, submit nothing,
  hand back fake ids. `RUNINFO` records `DRYRUN=yes` and `checkRun.sh`
  skips such runs.
- **Genome `human_hg38+mm39`** (hybrid human/mouse), on the IRIS tree.
- **Documentation, tracked:** `CLAUDE.md`, `ISSUES.md`,
  `docs/IRIS_CLUSTER_INFO.md`, `docs/LSF_SLURM_PORT.md`. Note these are
  tracked on the Slurm branches only.

### Changed

- **Dependencies are threaded as job ids, not name globs.** Slurm has no
  equivalent of `-w post_done(GLOB)`, so every call site captures `$JOBID`
  at submit and passes it forward. Two of the old globs were also wrong
  and are now exact: the merge waits on the `MAP_03` ids only, not on clip
  and bwa as well, and `__06__POST` waits on the alignment-summary job
  alone rather than on every `__05__STATS*`.
- **`--kill-on-invalid-dep=yes` on every `HOLD`.** `kill_invalid_depend`
  is off cluster-wide on IRIS; without the flag an orphaned job pends
  forever in `DependencyNeverSatisfied`.
- **One log directory per run**, `SLURM.PEMAP/<DTS>_<PID>_<SAMPLE>/`,
  exported as `PEMAP_RUNDIR`. The old layout recomputed the path from a
  fresh timestamp on every `QRUN`, scattering one run's logs across
  several directories so it could not be read — or checked — as a unit.
  Each job leaves `<jobid>.out` and `<jobid>.cmd` there; `--wrap` leaves
  no script artifact of its own.
- **Scratch moved out of the working directory** to
  `${PEMAP_SCRATCH_ROOT}/<DTS>/$(uuidgen -t)`, default
  `/scratch/core001/bic/$USER/PEMapper`. `pipe.sh` aborts if it cannot
  create it rather than running on with no scratch.
- **picard `TMP_DIR` is `/localscratch/$USER`** (node-local disk),
  overridable with `PEMAP_TMPDIR`. The JUNO paths `/fscratch` and
  `/scratch/socci` are both gone.
- **The picard heap is derived from `SLURM_MEM_PER_NODE`** minus a fixed
  `PEMAP_JVM_HEADROOM_MB` (default 9216), so `VMEM 32` still yields
  exactly `-Xmx23g` and the two can no longer drift. Under `CR_CPU_MEMORY`
  the request is a hard cgroup cap, so a memory request that "worked" on
  JUNO can be OOM-killed here; the headroom covers JVM overhead *and* the
  page cache picard's own writes charge to the same cgroup.
  `-XX:ParallelGCThreads=2 -XX:ConcGCThreads=2` is a static cap, not a
  tuning knob — enough picard JVMs on one node with GCs sized to the
  physical core count will bury it.
- **`bin/bwa` repointed** to
  `/usersoftware/core001/common/RHEL_8/bwa/v0.7.19/bin/bwa`, and `pipe.sh`
  now aborts on an empty `BWA_VERSION`. Bash skips a broken symlink during
  `PATH` lookup, so without that check a dead target silently resolves to
  whatever is next on `PATH`.
- **`runPEMapperMultiDirectories.sh` throttles on `squeue`**, not `bjobs`.
- **Genome configs repointed** at the IRIS reference tree
  `/data1/core001/rsrc/genomic/bic/assemblies`: `human_b37`, `mouse_mm10`,
  `human_hg38+mm39`, each verified on disk to have a FASTA, a picard
  `.dict` and a **bwa 0.7.19** index matching the installed binary.
  Retired configs moved to `lib/genomes/IRIS/` (still on dead `/juno` and
  `/rtsess01` paths) and `lib/genomes/JUNO/`; neither directory holds
  anything runnable.
- **`pipe.sh -g` lists genome *files*** (`-maxdepth 1 -type f`), so the
  two archive directories are not offered as genomes, and the lookup tests
  `-f` rather than `-e` so naming one gives "Not Defined" instead of
  trying to `source` a directory.
- **`SAMPLEDIRS` is absolutized before use**, keeping the scratch
  intermediates out of dotfile territory.
- **R1 → R2 derivation is anchored on the suffix** — `_R1_<digits>` for
  underscore names, the rightmost `.R1.` before `.fastq.gz` for
  dot-separated ones — so a sample name or parent directory containing
  `R1` is no longer rewritten. A name matching the `find` pattern but
  neither anchor is now fatal; previously the strip was a no-op and R2
  came back equal to R1. A missing R2 is fatal.
- **An empty read-length sniff is fatal**, instead of silently falling
  back to `MINLENGTH=35`.
- **`bin/picardV2` lost its `LSF` first-argument mode**, which
  self-submitted with `bsub`. It and `bin/picard.local` are now identical
  apart from whitespace; both are still called from `pipe.sh`.
- **`doRNAQC.sh` is disabled at the top of the file.** It is a standalone
  helper, not part of `pipe.sh`, and points at retired `/ifs/work`
  refFlat paths, `~/Code/Gist` and `bsub`. It prints what needs fixing and
  exits 0.
- **README rewritten** for the Slurm port.

### Fixed

- **`bin/getReadLength.py` and `bin/transpose.py` ported to Python 3.**
  There is no `python2` on IRIS; both had been failing silently.
- **`bin/clipAdapters.sh` no longer swallows cutadapt's exit status.** It
  ended on `deactivate` and a bare `wait` (always 0), so a cutadapt
  failure produced an empty CLIP fastq and a `COMPLETED` job.
- **`bin/transposeASMetrics.sh` runs under `pipefail`** and checks its
  input; as an unguarded pipeline a missing `___AS.txt` exited 0.
- **The picard wrappers fail hard when `TMP_DIR` cannot be created**
  rather than spilling tens of GB somewhere unintended. There is
  deliberately no `/tmp` fallback.

Both exit-status bugs were equally broken under LSF. `sacct` and the log
trailer report what the job script returned, so a wrapper that swallows
its payload's status makes every layer above it lie.

### Removed

- `bsub.sh`, `lsf.sh`, `sge.sh`, `sgeWrap.sh`, `cutadapt.off` and
  `runBwa.sh` moved to **`bin/attic/`**, deliberately off `PATH` since
  `pipe.sh` puts `$SDIR/bin` first. The LSF and SGE backends are kept as
  reference; neither is sourced. `bin/attic/` exists on the Slurm branches
  only — a checkout of `master`, `neo` or a `flavor/*` puts those files
  back at `bin/`, where they are needed.
- The `__07a_CLEANUP` job that removed `$SCRATCH` is **commented out in
  `pipe.sh`** for the duration of the port, by request. `__07b_CLEANUP`,
  which removes the pre-MarkDuplicates BAM/BAI, is active.

### Known issues

Tracked in `ISSUES.md`. In short: dot-separated `.R1.` FASTQ names are
verified offline but have never run on the cluster; there is no
human-only hg38 config because `H.sapiens/hg38` has no bwa index; the
archived genome configs under `lib/genomes/IRIS/` are not repointed.

### Validation

10 WES samples, 250 jobs, 250 `COMPLETED`, 0 OOM, 0 timeout. Probes and
job ids are recorded in `docs/IRIS_CLUSTER_INFO.md`.

## Earlier releases

Reconstructed from the tag messages; these predate this changelog.

| Tag | Date | What |
|---|---|---|
| `v_4.0.1-juno` | 2026-09-07 | Final JUNO version. Branch `juno`, one doc commit past `v_4.0.0`; not an ancestor of `v_4.1.0`. |
| `v_4.0.0` | 2026-09-01 | Release of the JUNO/Neo era, picard v2. The base of `v_4.1.0`. |
| `wgs_v_3.1` | 2023-11-04 | New script to merge bwa + AddReadGroups. |
| `wgs_v_2.3_preScatter` | 2018-03-25 | The version prior to the Scatter changes. |
| `v_2.3.1-dev` | 2017-05-22 | Dev test of the `TRIM_READS` option. |
| `v_2.2.1_SE` | 2017-03-25 | Converted to the single-end version (SEMapper). |
| `v_2.2.1` | 2017-03-25 | Last paired-end version before the SEMapper branch. |
| `v_2.2.0` | 2016-10-01 | Paired cutadapt. |
| `v_2.1.0` | 2016-07-26 | Fixed a `MIN_LENGTH` bug; better bsub options (LONG vs SHORT jobs). |
| `v_2.0.0` | 2015-09-30 | RC2, first fully working version on LSF. |
| `v_1.9.9` | 2015-09-29 | Start of the port from SGE to LSF. |
| `v_1.0.3` | 2014-04-12 | Fixed the path to transpose. |
| `v_1.0.2` | 2014-04-12 | Removed the `activate` command; no longer using a local install. |
| `v_1.0.1` | 2014-04-12 | Added `README.txt`. |
| `lastOPTVersion` | 2014-04-12 | Added the hybrid human/mouse genome (hg19+mm10). |
| `v_0.2.5` | 2014-03-02 | Genomes may be given by path, not only by name under `lib/`. |
| `v_0.2.3` | 2014-02-24 | Fixed the script name in the usage message. |
| `v_0.2.2` | 2014-02-24 | Added C. elegans (ce6). |
| `v_0.2.1` | 2014-01-20 | Changed the read-group `PU` variable to the run directory path. |
| `v_0.2.0` | 2014-01-20 | Allow multiple FASTQ directories for one sample. |
| `0.2.4` | 2014-02-25 | Fixed a bug in the transpose command. Tag is unprefixed, out of date order. |
| `v_0.1.1` | 2014-01-19 | Turned off debugging. |
| `v_0.1.0` | 2014-01-19 | Added picard stats. |
| `v_0.0.9` | 2014-01-19 | Comments on how to use `QRUN`. |
| `v_0.0.1` | 2014-01-19 | Comments on the BWA SAM and genome version variables. |
