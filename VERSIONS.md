# PEMapper — versions

What version of everything a run on this release uses. Nothing else:
changes are in `CHANGELOG.md`, configuration and internals in `CLAUDE.md`.

## This release

| | |
|---|---|
| Version | `v_4.1.0` |
| Date | 2026-09-08 |
| Base | `v_4.0.0` |
| Backend | `bin/slurm.sh` |

`pipe.sh` runs `git describe` against its own `$SDIR/.git` at submit time
and stamps the result into every BAM's `@PG` `VN:` field, so the version a
run actually recorded is readable back off the BAM.

## External tools

Measured on IRIS, 2026-09-08.

| Tool | Version | Pinned by |
|---|---|---|
| Slurm | 25.11.5 | cluster |
| bwa | 0.7.19 | `bin/bwa`, a committed symlink; `pipe.sh` puts `$SDIR/bin` first on `PATH` |
| picard | 2.25.5 | `bin/jar/picard.jar`, committed |
| Java | OpenJDK 23.0.1 | `PATH` |
| Python | 3.10.14 | `PATH`; there is no `python2` on IRIS |
| cutadapt | **unpinned** | `pip install cutadapt` into `bin/venv` |
| R | 4.5.1 | `PATH`; only for picard's `___INSHist.pdf` |

Two of these are not as fixed as the table looks:

- **cutadapt** has no version constraint, so two setups a month apart can
  get different versions. To reproduce a run exactly, record
  `bin/venv/bin/cutadapt --version` with the results.
- **`bin/bwa`** is a per-branch symlink. On `master`, `neo` and the
  `flavor/*` branches it points at a CentOS 7 path that does not exist on
  IRIS, and bash skips a broken symlink during `PATH` lookup, so `bwa`
  resolves to whatever is next instead of failing. Only `pipe.sh` on the
  Slurm branches aborts on an empty `BWA_VERSION`.

## Reference genomes

Live configs in `lib/genomes`. Each index was built with the same bwa the
pipeline runs.

| Config | Assembly | bwa index |
|---|---|---|
| `human_b37` | b37 | 0.7.19 |
| `mouse_mm10` | mm10 | 0.7.19 |
| `human_hg38+mm39` | hg38 + mm39 hybrid | 0.7.19 |

## Tag format

`v_<major>.<minor>.<patch>`. Flavor and cluster branches carry their own
tags off this line of history; see `CLAUDE.md`, "Branch model".
