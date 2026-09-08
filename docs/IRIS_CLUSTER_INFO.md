# IRIS cluster facts

Measured, not assumed. Everything here was probed on IRIS (MSKCC) between
2026-09-01 and 2026-09-03, mostly from `isca006`, during the PEMapper Slurm
port. Job ids are kept so a claim can be re-checked with `sacct`.

Design decisions that follow from these facts live in `CLAUDE.md`; open work
lives in `ISSUES.md`. This file is facts only.

## Scheduler

Slurm 25.11.5, RHEL 8.

| Setting | Value | Consequence |
|---|---|---|
| `SelectTypeParameters` | `CR_CPU_MEMORY` | `--mem` is a hard cgroup cap. Under LSF `rusage[mem=]` was advisory, so a request that "worked" on JUNO can be OOM-killed here. |
| Default account | `core001` (also `test01`) | |
| Default partition | `cpu` | **Denies `core001`.** `-p` must always be explicit. |
| `EnforcePartLimits` | `ALL` | A job over the partition `MaxTime` is rejected at submit, not queued. |
| `DefaultTime` | `02:00:00` | On every partition. |
| `DefMemPerCPU` | 2048 MB | |
| `DependencyParameters` | `(null)` | `kill_invalid_depend` is **not** set cluster-wide, so an orphaned `afterok` job pends forever in `DependencyNeverSatisfied` unless submitted with `--kill-on-invalid-dep=yes`. |
| `MaxJobCount` | 400000 | No `MaxSubmitJobs` limit on the association. |
| `MaxCPUsPerNode` | 52 on `cpushort` | Max `ALLOC` in this pipeline is 8. |
| `JobAcctGatherType` | `jobacct_gather/cgroup` | See "Memory accounting". |

Slurm has no `post_done(GLOB)` equivalent: `--dependency` accepts job ids
only, and `singleton` matches an exact name, not a glob.

Slurm writes **nothing** of its own into the `-o` file — no epilogue, unlike
LSF. A job that OOMs, times out or exits non-zero leaves a log that can look
identical to a good one.

## Partitions

All three verified accessible to `core001`.

| Partition | `MaxTime` | Notes |
|---|---|---|
| `cpushort` | `02:00:00` | Pins `cpushort_qos`; do not set `--qos`. |
| `cmobic_short` | `03:00:00` | Allows `normal,priority`, defaults correctly. |
| `cmobic_cpu` | `7-00:00:00` | |
| `cmobic_preempt` | — | `PreemptMode=REQUEUE`. Stay off it for production. |
| `bic_devs` | 30d, 1 node | Debugging only. |

## Filesystems

- **Dead:** `/juno`, `/rtsess01`, `/fscratch`, `/ifs/work`, `/admin/lsfjuno`.
- **Live:** `/data1/core001`, `/usersoftware/core001`, `/scratch`,
  `/ifs/datadelivery`, `/ifs/instruments`. There is no `/scratch/socci`.
- `df /scratch` reports 2.0T at 100% — that is a **per-directory quota view
  and is misleading**. `/scratch/core001` reports 100T with 97T available and
  writes succeed.
- `/localscratch` is node-local disk. This is where picard's tens of GB of
  sort spill belongs; a shared filesystem is the wrong answer.
- Compute nodes inherit the submit environment and can see `/data1`,
  `/usersoftware` and `~/bin`. `TMPDIR=/tmp` there.
- Reference tree: `/data1/core001/rsrc/genomic/bic/assemblies`.
  `H.sapiens/hg38` has a FASTA and a `.dict` but **no bwa index**.

## Toolchain

| Tool | Version | Note |
|---|---|---|
| `bwa` | 0.7.19 | `/usersoftware/core001/common/RHEL_8/bwa/v0.7.19/bin/bwa` |
| `java` | 23.0.1 | Runs the committed picard 2.25.5 fine. |
| `python` | 3.10.14 | Spack build on `PATH`. **No `python2`.** |
| `/usr/bin/time` | absent | Nothing else provides a page-cache-free RSS. |
| `~/bin/bsub` | — | SchedMD LSF-compat shim. No `-w`/dependency support, no `-R`. Not usable for this pipeline. |
| `~/bin/sbatch` | — | Personal script-rewrite wrapper. Call `/usr/bin/sbatch` directly to stay out of it. |

`git --git-dir=... describe` does **not** trip git's `safe.directory`
ownership check from a compute node.

A partial `--export` list triggers a user-env-retrieval probe that is broken
on `isca001` / `bic_devs`; `--export=ALL` is fine.

## Memory accounting — `MaxRSS` does not mean what it looks like

`JobAcctGatherType=jobacct_gather/cgroup` reads the cgroup memory watermark,
which **includes page cache**. Any job streaming tens of GB fills its cgroup
with cache until it reaches `--mem`, so `MaxRSS` tracks I/O volume clipped at
the request, not memory demand.

Proof — 60 `MAP_01` cutadapt jobs, `--mem=5G`, cap `5242880K`:

```
MaxRSS across all 60:  5241408K .. 5243972K    (2.6 MB spread; some over cap)
```

cutadapt does not use 5.000 GiB of anonymous memory sixty times running.
Per step over the 2026-09-02 WES runs (GiB):

| Step | req | cpus | min | p50 | max |
|---|---|---|---|---|---|
| `MAP_01` clip | 5G | 2 | 5.00 | 5.00 | 5.00 |
| `MAP_02` bwa | 32G | 8 | 27.43 | 32.00 | 32.00 |
| `MAP_03` ARRG | 32G | 2 | 19.79 | 32.00 | 32.00 |
| `05__MD` | 32G | 2 | 28.05 | — | 32.00 |
| `04__MERGE` | 32G | 2 | 12.37 | — | 23.55 |
| `05__STATS.as` | 32G | 2 | 2.49 | — | 19.10 |
| `POST`/`CLEANUP`/`STATUS` | 2G | 1 | 0.00 | — | 0.02 |

`MaxRSS` lives on the `.batch` step, not the allocation — `sacct -X` hides
it. `TRESUsageInMax` reads the same cgroup, so it is no better.

Java sizes its own heap at 25% of the cgroup cap if left alone
(`MaxHeapSize = 1879048192` on a 7G allocation). `SLURM_MEM_PER_NODE` is
present and exact in the job environment (job `11372226`, `--mem=7G` →
`SLURM_MEM_PER_NODE=7168`); `SLURM_MEM_PER_CPU` is empty when submitting
with `--mem`. Java 23 does read the cgroup CPU limit and picks
`ParallelGCThreads=2` on a `-c 2` allocation.

## Job state — what `sacct` and the logs report

Probed 2026-09-01.

| Test | Job | Result |
|---|---|---|
| `sacct` from a compute node | 11135980 | Works (`SACCT_RC=0`). |
| Exit code through `--wrap` | 11135996 | Log ends `#PEMAP_EXIT=2`, `sacct` `FAILED 2:0`. Code propagates, so `afterok` is unaffected. |
| OOM | 11136001 | `State=OUT_OF_MEMORY`, **`ExitCode=0:125`** although the script exited 137. |
| Walltime | 11136004 | `State=TIMEOUT`, and the log holds **only** Slurm's cancellation notice — no trailer at all. |

Two consequences: **match on `State`, never `ExitCode`** (anything not
`COMPLETED` is a failure — `FAILED`, `TIMEOUT`, `OUT_OF_MEMORY`, `CANCELLED`,
`NODE_FAIL`), and a cancelled job never runs so it has **no log at all**.

Job ids around `8888002` are *real past jobs* on this cluster and `sacct`
answers for them. To test purge behaviour use ids above the counter (~11.1M).

## Validation runs

**Smoke test, 2026-09-01** — `human_b37` against
`../testFastq/FASTQ/FAUCI_0132_A222HTVLT4/Project_15731_B/Sample_UT-CART_IGO_15731_B_9`
(1 pair, ~7 MB each, 89,971 read pairs, 151 bp), run from `../Pass2`,
jobs 11130071-11130079, production partitions. All nine COMPLETED, whole
pipeline under two minutes. The run confirmed `MINLENGTH=75` reached
cutadapt, `___ASt.txt` was populated, picard used `TMP_DIR=/localscratch`,
and the BAM `@PG` carried `VN:v_4.0.0-1-gf39d578` with the bwa 0.7.19
command line.

| Job | Class / partition | `-c` | ReqMem | Elapsed |
|---|---|---|---|---|
| MAP_01 clip | MEDIUM `cmobic_short` | 2 | 5G | 00:00:08 |
| MAP_02 bwa | LONG `cmobic_cpu` | 8 | 32G | 00:00:21 |
| MAP_03 RG | LONG `cmobic_cpu` | 2 | 32G | 00:00:06 |
| 04 MERGE | LONG `cmobic_cpu` | 2 | 32G | 00:00:04 |
| 05 STATS.as | LONG `cmobic_cpu` | 2 | 32G | 00:00:13 |
| 05 STATS ins | LONG `cmobic_cpu` | 2 | 32G | 00:00:23 |
| 05 MD | LONG `cmobic_cpu` | 2 | 32G | 00:00:09 |
| 06 POST | SHORT `cpushort` | 1 | 2G | 00:00:02 |
| 07b CLEANUP | SHORT `cpushort` | 1 | 2G | 00:00:02 |

**Multi-pair, 2026-09-01** — jobs 11137307-11137319. Source FASTQ split into
two disjoint halves as lanes L003/L004: 13 jobs, `HOLD` with two ids and
`HOLDANY` with twelve. All 12 pipeline jobs COMPLETED.

> Do **not** fake a second pair by copying the first. The merged BAM then
> holds each read name twice and MarkDuplicates dies with `Value was put into
> PairInfoMap more than once` — the fixture is physically impossible, not a
> pipeline bug.

**Negative test, 2026-09-01** — jobs 11137183-11137192. `GENOME_BWA` pointed
at a non-existent index: `MAP_02` FAILED `1:0`, all seven downstream jobs
CANCELLED by `--kill-on-invalid-dep=yes` rather than left pending, `$SCRATCH`
survived, and `__08__STATUS` **still ran** and wrote its report.

**Full scale, 2026-09-02/03** — 10 WES samples, 250 jobs, ~19 GB gzipped
FASTQ in and 11-14 GB `___MD.bam` out per sample. `250/250 COMPLETED`,
`250/250 #PEMAP_EXIT=0`. No OOM, no walltime kill.

All runs used `_R1_`-style FASTQ names; the `.R1.` path has not been
exercised on the cluster (`ISSUES.md` #1).
