#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
set -euo pipefail

# Slurm exports: build_name, configure_arguments
# Time, partition, cpus, gpus, output set by charmm-test

echo "=== BUILD ${build_name} === $(date)"
echo "configure: ${configure_arguments}"

module load anaconda/miniconda-latest
eval "$(conda shell.bash hook)"
conda activate "$HOME/testing/env/test"

cd "$HOME/testing"

if [[ ! -d "install-${build_name}" ]]; then
    echo "Creating new CHARMM tree: install-${build_name}"
    charmm/tool/NewCharmmTree "install-${build_name}"
fi

rm -rf "install-${build_name}/build/cmake"

cd "install-${build_name}"
./configure --with-ninja ${configure_arguments}
ninja -j${SLURM_CPUS_PER_TASK:-4} -Cbuild/cmake install

echo "=== BUILD ${build_name} DONE === $(date)"
