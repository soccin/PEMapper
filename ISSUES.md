# PEMapper — Issues

IRIS / Slurm / RHEL 8. Slurm only; a scheduler-agnostic build is out of
scope.

- Architecture, conventions, the `QRUN` contract: `CLAUDE.md`
- What changed, per release: `CHANGELOG.md`
- Tool and reference versions: `VERSIONS.md`
- Measured cluster facts, probes, validation runs: `docs/IRIS_CLUSTER_INFO.md`
- How the LSF → Slurm port was done: `docs/LSF_SLURM_PORT.md`

None of it is repeated here.

## Open

**#1 `.R1.` FASTQ names have never run on the cluster** · `verification`
`low` — The dot-separated rename branch is verified offline only; every
cluster run to date used `_R1_`. Confirm with `PEMAP_DRYRUN=1` on a
dot-named pair before trusting it on real data. `_R1_` path is unaffected.

**#2 No standalone hg38 genome** · `enhancement` `blocked` —
`H.sapiens/hg38` has `hg38.fasta` + `hg38.dict` but no bwa index. Build a
0.7.19 index if a human-only hg38 run is ever wanted.

**#3 Archived genome configs not repointed** · `enhancement` `wontfix?` —
`lib/genomes/IRIS/{human_b37+mm10,human_GRCh38}` still carry dead `/juno`
and `/rtsess01` paths. Repoint on demand. `mouse_GRCm38` is **dead, not
deferred**: GRCm38 is absent from the IRIS tree, `M.musculus/GRCm39`
replaced it.

**#4 `doRNAQC.sh` unported** · `enhancement` `low` — Guarded: prints what is
broken and exits 0 (`012019d`). Standalone helper, not called by `pipe.sh`.
Reviving needs refFlat repointed at `/data1/core001/rsrc`, a replacement for
`~/Code/Gist/getGenomeBuild.sh`, and its two `bsub` calls converted to
`QRUN`. Nobody is asking for it.

**#5 `picardV2` and `picard.local` are duplicates** · `cleanup` `low` —
Byte-identical bar two blank lines since the LSF branch came out (`f8a08bb`).
Collapsing to one wrapper means editing four `pipe.sh` call sites. Inert;
not worth the risk near a tag.

**#6 No real max-RSS measurement** · `enhancement` `low` — Would need a
`getrusage(RUSAGE_CHILDREN)` shim in the job wrapper emitting
`#PEMAP_MAXRSS_KB=` beside `#PEMAP_EXIT=`. Nothing needs it until someone
wants to trim a `VMEM`. See #8.

## Closed as by-design — do not "fix"

**#7 `07a` `rm -rf $SCRATCH` stays commented out** — per user, for the port's
duration; keeping intermediates makes failures debuggable. Re-enabling needs
`HOLD $MERGE_ID` as written. `07b` (pre-MD BAM/BAI) stays active.

**#8 `sacct MaxRSS` is not a memory measurement here** —
`jobacct_gather/cgroup` counts page cache, so it tracks I/O volume clipped at
`--mem`. **Never trim a `VMEM` on it.** Evidence and per-step numbers:
`docs/IRIS_CLUSTER_INFO.md`.

**#9 picard GC caps stay static** — `-XX:ParallelGCThreads=2
-XX:ConcGCThreads=2` in `bin/picardJvm.sh`. Java 23 derives the same 2 from
the cgroup, so they look redundant; they are not. Deriving from
`SLURM_CPUS_PER_TASK` is worse — unset, it falls through to the node's core
count.

**#10 `__08__STATUS` holds on every job id** (~`3N+7` for N pairs) — fine at
tested sizes. If a huge sample ever hits a dependency-string limit, holding
the leaf jobs only is equivalent, since `--kill-on-invalid-dep` makes leaves
terminal.

## Closed — port work

`bin/slurm.sh` Slurm backend + `QRUN` · dependency rework to explicit job ids
· run-status reporting (`jobs.tsv`, `sacct`, `#PEMAP_EXIT=` trailer,
`checkRun.sh`, `__08__STATUS`) · exit-status hygiene in `clipAdapters.sh` and
`transposeASMetrics.sh` · Python 2 → 3 (`getReadLength.py`, `transpose.py`) ·
`bin/bwa` dangling symlink → 0.7.19 · `SAMPLEDIRS` absolutized · `MINLENGTH`
per-pair · `PEMAP_SCRATCH_ROOT` default · picard `TMP_DIR` → `/localscratch`
· JVM heap derived from `SLURM_MEM_PER_NODE` (`5c2c973`) · `squeue` throttle
in `runPEMapperMultiDirectories.sh` · genome configs repointed (`169ec88`,
`550b963`, `d02c9a5`) · `.R1.` rename anchored on suffix (`a22e67e`) ·
`pipe.sh -g` skips archive dirs (`a9732d4`) · dead LSF/SGE code to
`bin/attic` (`7704c7a`, `ca53e56`) · `picardV2` LSF branch dropped
(`f8a08bb`).
