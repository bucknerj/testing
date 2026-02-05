#!/bin/bash
#SBATCH --time=4:00:00
#SBATCH -p gpu2080
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1

SLURM_NTASKS=4

echo "BEGIN BUILD SCRIPT $(date)"

echo "DETECTED: build name ->${build_name}<-"
echo "DETECTED: configure arguments ->${configure_arguments}<-"

module load anaconda/miniconda-latest
eval "$(conda shell.bash hook)"
conda activate "$HOME/testing/env/test"

pushd "$HOME/testing"

if [[ ! -d "install-$build_name" ]]; then
  echo "creating new charmm tree install-$build_name"
  charmm/tool/NewCharmmTree "install-$build_name"
fi

if [[ -d "install-$build_name/build/cmake" ]]; then
  echo "removing previous build dir install-$build_name/build/cmake"
  rm -rf install-$build_name/build/cmake;
fi

pushd "install-$build_name"

echo "start configure script..."
./configure --with-ninja $configure_arguments
echo "... configure script finished"

echo "begin compile using ninja..."
ninja -j$SLURM_NTASKS -Cbuild/cmake install
echo "... finished with ninja"

echo "END BUILD SCRIPT $(date)"
