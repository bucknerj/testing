#!/bin/bash
#SBATCH --nodes=1
set -euo pipefail

# Slurm exports: test_name, test_args (includes 'output' as last arg)
# Time, partition, ntasks, cpus, gpus, output set by charmm-test

echo "=== TEST ${test_name} === $(date)"
echo "test_args: ${test_args}"

module load anaconda/miniconda-latest
eval "$(conda shell.bash hook)"
conda activate "$HOME/testing/env/test"

cd "$HOME/testing/install-${test_name}/test"

# Link sccdftb data if needed
if [[ "${test_name}" == "sccdftb" ]] && [[ ! -L "./sccdftb.dat" ]]; then
    ln -s "$HOME/testing/sccdftb_data/sccdftb.dat" sccdftb.dat
fi

# Run test suite — test.com produces output.rpt for grading
# Grading is done separately by: charmm-test grade
/usr/bin/tcsh ./test.com ${test_args} 2>&1 | tee test.log || true

echo "=== TEST ${test_name} DONE === $(date)"
