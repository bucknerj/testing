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
