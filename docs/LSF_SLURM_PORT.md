# Porting PEMapper from LSF to Slurm

The record of the JUNO/LSF 10.1 → IRIS/Slurm 25.11.5 port, done
2026-09-01/03 on the `iris` branch. Kept because the same translation is
owed to every `flavor/*` branch still on `bin/attic/lsf.sh`, and because
several decisions here look wrong until you know what was measured.

- Current architecture and conventions: `CLAUDE.md`
- Cluster facts, probes, validation runs: `docs/IRIS_CLUSTER_INFO.md`
- Open work: `ISSUES.md`

## Strategy: keep the contract, replace the backend

`pipe.sh` never talked to LSF directly — every step went through the `QRUN`
shell function in `bin/lsf.sh`. The port wrote `bin/slurm.sh` as a drop-in
with the **same positional-keyword grammar**, so the diff to `pipe.sh`
stayed reviewable and the SGE implementation stayed meaningful as reference:

```
QRUN ALLOC JOBTAG [HOLD|HOLDANY "<jobid list>"] [VMEM total_gb] [SHORT|MEDIUM|LONG] command args...
```

`source $SDIR/bin/lsf.sh` → `source $SDIR/bin/slurm.sh` on `pipe.sh:11` is
the whole switch, and remains the reliable way to tell which line a checkout
is on.

## Flag translation

| LSF (`bin/attic/lsf.sh`) | Slurm (`bin/slurm.sh`) | Note |
|---|---|---|
| `-n $ALLOC` | `-N 1 -n 1 -c $ALLOC` | LSF slots are cores. A bare Slurm `-n` means **tasks** and would run the command N times. |
| `-R rusage[mem=$((TOTAL/ALLOC))]` | `--mem=${TOTAL}G` | Do **not** divide. Slurm `--mem` is total per node. |
| `-w post_done(PATTERN)` | `--dependency=afterok:<id>:<id>…` | Ids only, no glob. Omit the flag entirely when the list is empty — `--dependency=afterok:` is a submit error. |
| (n/a) | `--kill-on-invalid-dep=yes` | Required here; `kill_invalid_depend` is off cluster-wide. |
| `-W 359` | `-t 359` | Bare integer is minutes in both. Safe. |
| `-W 24:00` | `-t 24:00:00` | **Footgun:** LSF `24:00` is 24 *hours*, Slurm `24:00` is 24 *minutes*. |
| `-J $QTAG` | `-J $QTAG` | Unchanged. |
| `-o $LSFDIR/` | `-o $LOGDIR/%j.out` | Slurm has no trailing-slash auto-naming; the directory must pre-exist. |
| `-R cmorsc1` | (dropped) | JUNO resource group. |
| stdout+stderr merged | merged when only `-o` is given | Same behaviour, no `-e` needed. |
| `$LSF_SERVERDIR` version sniff | deleted | Replaced by the time-class → partition table. |
| `LSF_TIME_OVERRIDE` | `PEMAP_TIME_OVERRIDE` | Plus `PEMAP_PARTITION_*`. |
| `QSYNC=#` | deleted | Unused. |

Submission mechanics that differ:

- Read the job id from `sbatch --parsable`, not by scraping `Job <N>` with perl.
- `--wrap="$*"` reproduces the LSF behaviour exactly: `pipe.sh` escapes
  redirection as `\>\>`, the calling shell unescapes it, and `--wrap`
  re-interprets it under `/bin/sh`. Verified equivalent.
- `--export=ALL` (the default). A **partial** `--export` list triggers a
  user-env-retrieval probe that is broken on `isca001`/`bic_devs`.
- **Scrub inherited `SLURM_*`** before calling `sbatch`. Submitting from
  inside an interactive allocation otherwise leaks a stale `SLURM_JOB_ID`
  into every child job via `--export=ALL`.
- Call `/usr/bin/sbatch` through `bin/sbatch.sh` so a personal `~/bin/sbatch`
  wrapper is not in the loop.
- Log tree `LSF.PEMAP/` → `SLURM.PEMAP/`, and the resolved `sbatch` line is
  written beside each log as `.cmd` — with `--wrap` there is no script
  artifact to inspect afterwards.

## The dependency graph had to be rebuilt

This was the largest single change. LSF let `pipe.sh` wait on a whole *class*
of jobs by name pattern — `-w post_done("${TAG}_MAP_*")`. **Slurm has no
equivalent:** `--dependency` accepts job ids, and `singleton` matches an
exact name, not a glob.

So every call site now captures `$JOBID` at submit time and threads id lists
forward explicitly (`CLIP_ID` → `BWA_ID` → `MAP_IDS` → `MERGE_ID` → …).
`HOLD "$MAP_IDS"` must be quoted; it is one argument holding a list.

Two behaviour changes were taken deliberately, because the globs had been
over-waiting:

- `${TAG}_MAP_*` also matched MAP_01/02, so MERGE waited on the clip and bwa
  jobs as well. Holding the MAP_03 ids only is equivalent and exact.
- `${TAG}__05__STATS*` matched both InsertSize and AlignmentSummary, but
  `POST` only consumes `___AS.txt`. It now holds `$ASTAT_ID` alone.

Job names stopped being load-bearing (the two colliding `07b_CLEANUP` jobs
were renamed `07a`/`07b`) — with one exception: `bin/checkRun.sh` matches
`__08__STATUS` by name to keep the status job out of a run's totals.

## Memory stopped being advisory

Under LSF, `rusage[mem=]` was a scheduling hint. Under `CR_CPU_MEMORY` it is
a hard cgroup cap and the job is OOM-killed, so **requests that "worked" on
JUNO can fail here.** `MAP_03` asked `VMEM 26` while the wrapper ran
`java -Xmx23g`; JVM overhead puts real RSS at 24-26 GB, so it would have
been killed. Raised to `VMEM 32`.

The wrappers also hard-coded `-Xmx23g` with no connection to what their
`QRUN` call site requested, so the two could drift. `bin/picardJvm.sh` now
derives the heap from `$SLURM_MEM_PER_NODE` minus a **fixed** headroom
(default 9216 MB), which reproduces `-Xmx23g` at `VMEM 32` exactly. Fixed
rather than proportional, so the validated pairing survives unchanged.

Sizing the requests from measurement turned out to be impossible on IRIS —
`sacct MaxRSS` counts page cache. See `docs/IRIS_CLUSTER_INFO.md`; the
requests are closed on negative evidence (250/250 jobs COMPLETED) instead.

## The epilogue that vanished

LSF appended `Successfully completed.` / `Exited with exit code N` to every
job's output file, so a `grep` over the log tree answered "did that run
work?". **Slurm writes nothing of its own into the `-o` file.** A job that
OOMs, times out or exits non-zero leaves a log that can look identical to a
good one. This was the last blocker on the port and its absence was
considered fatal.

Replaced with three independent records — `jobs.tsv` (the id manifest),
`sacct` (the authority, matched on `State`), and a `#PEMAP_EXIT=<rc>`
trailer appended by every `--wrap` — plus `SUBMIT_COMPLETE` in `RUNINFO` to
catch a truncated submission, and an `__08__STATUS` job holding `HOLDANY` on
the whole run. Each covers the others' blind spots; `CLAUDE.md` says which,
and the probes behind each claim are in `docs/IRIS_CLUSTER_INFO.md`.

One prerequisite deserves calling out: **two wrappers were lying about their
exit status** and had to be fixed first, or every layer above them —
`sacct` included — would have reported COMPLETED. `clipAdapters.sh` ended on
`deactivate`, and `transposeASMetrics.sh` was an unguarded pipeline. This
class of bug predates the port; it was equally broken under LSF.

## Breakage found along the way

Not scheduler differences — things that had rotted and were only noticed
because the port re-ran everything:

| What | Was | Now |
|---|---|---|
| `bin/getReadLength.py` | Python 2; no `python2` on IRIS, failed silently, `MINLENGTH` came out empty and cutadapt fell back to 35 | Python 3; `pipe.sh` aborts on an empty value |
| `bin/transpose.py` | Python 2, so `___ASt.txt` was written empty | Python 3 |
| `bin/transposeASMetrics.sh:5` | echoed `SDIR=` to stdout, which `pipe.sh` redirects into `___ASt.txt` | silenced |
| `bin/bwa` | dangling symlink to a CentOS 7 path; bash skips broken symlinks on `PATH`, so it silently fell through to `~/bin/bwa` | pinned at 0.7.19; `pipe.sh` aborts on empty `BWA_VERSION` |
| `runPEMapperMultiDirectories.sh` | throttle called `bjobs`, absent on IRIS, so `NUMJOBS=0` and the throttle was disabled | `squeue -h -u $USER` |
| picard `TMP_DIR` | `/fscratch/socci` → `/scratch/socci`, both gone | `${PEMAP_TMPDIR:-/localscratch/$USER}`, aborts if it cannot be created |
| `MINLENGTH` | exported inside the FASTQ loop only when empty, so pair 1's read length applied to every later pair | recomputed per pair |
| `SAMPLEDIR` relative | made `BASE1` start with `..`, so scratch intermediates were dotfiles | absolutized with `(cd && pwd)` |
| `exit -1` | yields status 255 | `exit 1` |
| `PEMAP_SCRATCH_ROOT` | defaulted to `…/bic/socci/PEMapper` from the handoff — `socci` is a **directory naming convention, not `$USER`**; the IRIS account is `soccin`, so everyone else wrote into that one directory | `…/bic/${USER:-$(id -un)}/PEMapper`, and `pipe.sh` aborts if `$SCRATCH` cannot be created |

## Deliberately not done

- **No scheduler-agnostic build.** Out of scope by decision. `bin/attic/lsf.sh`
  and `bin/attic/sge.sh` are kept as reference, not as a runtime option.
- **The LSF self-submit path was deleted, not ported** — `bin/picardV2`'s
  `LSF` first-argument mode (`f8a08bb`) and `bin/bsub.sh`.
- **`~/bin/bsub`**, the SchedMD LSF-compat shim, was evaluated and rejected:
  no `-w`, no `-R`, so the dependency graph cannot be expressed through it.
