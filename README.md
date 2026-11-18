# CHARMM Testing Pipeline

Slurm-based build, test, and grade pipeline for CHARMM on the ada5000 cluster.

## Setup

```bash
# One-time: create conda environment and clone CHARMM source
bash setup.bash

# Verify everything is in place
charmm-test prereqs
```

## Usage

```bash
# Show all configurations
charmm-test list

# Build and test everything (chained via Slurm dependencies)
# Pulls latest CHARMM source first
charmm-test run

# Or build/test specific configs
charmm-test run gpu sccdftb misc

# Build only (skip git pull with --no-pull)
charmm-test build lite
charmm-test build --no-pull gpu

# Test only (assumes already built)
charmm-test test gpu

# Check Slurm job status
charmm-test status

# Grade results after tests complete
charmm-test grade
charmm-test grade gpu --tol 0.001
charmm-test grade --xml results.xml    # JUnit XML output
charmm-test grade --xfail xfail.txt    # skip known failures

# Promote output to benchmark
charmm-test bench sccdftb

# Archive old results
charmm-test clean
```

## Prerequisites

Run `charmm-test prereqs` for an automated check. Requirements:

### Directory layout

```
~/testing/
├── charmm-test          # this script (must be executable)
├── setup.bash           # one-time environment setup
├── charmm/              # CHARMM source (git clone)
├── env/test/            # conda environment prefix
├── sccdftb_data/        # (optional) SCCDFTB parameters
└── install-<name>/      # per-config build trees (created automatically)
```

### Software (in conda env or via modules)

- Python 3.8+ (stdlib only, no third-party packages)
- Slurm (sbatch, squeue) on the cluster
- Ninja build system
- CMake
- Fortran/C/C++ compilers (gcc/gfortran or Intel)
- MPI (OpenMPI or Intel MPI) for parallel configs
- CUDA toolkit for GPU configs
- tcsh (`/usr/bin/tcsh`) for test.com
- Git

See `setup.bash` for the exact `conda create` invocation.

## Files

| File | Purpose |
|------|---------|
| `charmm-test` | Main CLI tool (self-contained, no external deps) |
| `setup.bash` | One-time conda environment and CHARMM clone setup |
| `nightly` | Cron script: test master when it has changed, mail the report |

## Nightly runs

`nightly` is meant for the crontab of the account that owns `~/testing`:

```
15 2 * * * $HOME/testing/nightly >> $HOME/testing/nightly-state/cron.log 2>&1
```

Each night it

1. fetches `master` and stops if it is the commit the last nightly run
   tested, so nothing is submitted on a day without changes;
2. looks at the queues and sends the jobs to the candidate partition with
   the fewest pending jobs (ties go to the one with more idle nodes);
3. archives the old outputs, builds and tests every configuration, and
   waits for the jobs;
4. grades against the benchmark, writes `reports/<date>.md` with
   `charmm-test report` (regressions and fixes against the previous
   report), and mails it.

Settings are in `~/testing/nightly.conf` (optional, bash):

| Setting | Default | Meaning |
|---|---|---|
| `MAILTO` | unset | Address the report is mailed to; unset means no mail |
| `REMOTE` | `origin` | Remote name or URL to fetch `master` from. Keep the file mode 600 if the URL carries a token |
| `CPU_PARTITIONS` | `cpu gpuA5500` | Candidates for jobs that need no GPU |
| `GPU_PARTITIONS` | `gpuA5500 gpu2080 ada5000 ada6000` | Candidates for the `gpu` and `gpu2` configurations |
| `MAX_WAIT_HOURS` | `10` | After this the remaining jobs are cancelled and a partial report is sent |

`nightly --dry-run` shows what it would do (the commit check and the
partition choice) without changing anything; `nightly --force` runs even
if master has not moved. Each run leaves its logs in
`~/testing/nightly-state/<date>-<commit>/`. A run that cannot start (the
checkout is not on master, has local changes, the fetch fails, harness
jobs are still queued) mails that instead of a report.

The mail's subject line carries the number of regressions, so a quiet
night reads `0 new failures` without opening it.

## Benchmark policy

The benchmark (`install-*/test/bench/`) is what every run is graded
against. `nightly` never changes it: a benchmark that follows master
automatically would absorb a regression the night after it happened.

Regressions are found a different way. `charmm-test report` compares each
run with the previous run's results, test by test, so a test that passed
yesterday and fails today is reported whatever the benchmark says. The
benchmark only decides the numbers a non-self-checking test is diffed
against.

Rotate it by hand, with `charmm-test bench`, when one of these happens:

1. **A release is tagged.** The tagged commit becomes the benchmark.
2. **A merge changes numbers on purpose** (a corrected energy term, a new
   default). Promote once the run after the merge shows only the expected
   diffs, so they stop being reported every night.
3. **A testcase is added or rewritten** and has no benchmark output yet.
   Promote just the configurations that run it.

Before promoting: the run being promoted must be from a clean
`charmm-test clean` + `run`, its regressions list must be empty or
understood, and no build may have failed. A crashed test stays a failure
after promotion (the grade checks termination before it looks at the
benchmark), so promoting cannot hide a crash.

After promoting: record the commit, the date and the reason in
`BENCH_PROVENANCE.txt`. `charmm-test bench` keeps the previous benchmark
as `bench.<timestamp>`; keep the last three and delete older ones.

## Generating documentation

The script is self-documenting via Python docstrings:

```bash
# pdoc can generate HTML directly from the script
pdoc ./charmm-test -o docs/

# If pdoc requires a .py extension:
ln -s charmm-test charmm_test.py
pdoc charmm_test -o docs/
```

## Testing with Jenkins on morrison

Three Jenkins pipelines run on `morrison`, one per build flavor, each
defined by a Groovy file at the root of this repo:

| Pipeline | File | Build flavor |
|---|---|---|
| `pipeline-dev` | `pipeline-dev.groovy` | dev branch, GNU + OpenMPI, ~13 feature configs |
| `pipeline-stable` | `pipeline-stable.groovy` | stable branch, GNU + OpenMPI |
| `pipeline-intel` | `pipeline-intel.groovy` | Intel compilers + Intel MPI |

Each pipeline iterates over the configs returned by
`charmm-test list --json`, builds each one into `install-<name>/`,
runs the test.com suite, runs the pyCHARMM pytest suite (where
applicable), and publishes JUnit XML to Jenkins. The grading step
uses `charmm-test grade` with the same noise filters and tolerance
as a local invocation.

### Environment

Jenkins pipelines activate the `workshop` micromamba env on morrison.
Its specification lives at the repo root:

| File | Purpose |
|---|---|
| `workshop-env.yaml` | Human-edited intent: channels and top-level packages with version constraints. Edit this when adding/removing dependencies. |
| `workshop-env-lock.yaml` | Full snapshot of resolved versions and builds, refreshed after intentional env changes. Use this when you need an exact, reproducible state. |

Recreate or sync the env on morrison:

```bash
# Fresh install
micromamba env create -n workshop -f workshop-env.yaml

# Update an existing env to match the spec
micromamba install -n workshop -f workshop-env.yaml
```

After intentionally changing the env, refresh both files and commit
them together:

```bash
micromamba env export -n workshop --from-history > workshop-env.yaml
micromamba env export -n workshop                > workshop-env-lock.yaml
```

Version pins worth knowing about:

- `cuda-version<13` — CUDA 13.x dropped support for Volta architecture
  (sm_70), which is the Quadro GV100 on morrison. A bumped
  `cuda-nvrtc` from CUDA 13.x will make OpenMM kernel JIT-compilation
  fail with `invalid value for --gpu-architecture`.
- `pytorch[build="cuda*"]`, `libtorch[build="cuda*"]`,
  `openmm-torch[build="cuda*"]` — force the CUDA variants. Without
  these, conda-forge may resolve to CPU-only builds even when CUDA is
  available, silently changing test numerics.

## Grading

`charmm-test grade` checks each test output for:
1. Expected failures (xfail list)
2. Missing output / abnormal termination
3. Self-reported PASS/FAIL/SKIP
4. Numerical diff comparison (output vs benchmark) with tolerance

The numerical comparison is ported from compare.awk (C.L. Brooks III, 2003)
and handles Fortran D-notation, expected diff patterns, and relative tolerance.
Default tolerance is 0.0001 (1e-4), suitable for CHARMM MD energy values.
