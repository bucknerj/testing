#!/bin/bash

module load anaconda/miniconda-latest
eval "$(conda shell.bash hook)"

env_prefix="/home/bucknerj/testing/env/test"

conda create -p "$env_prefix"
conda activate "$env_prefix"

conda install -c conda-forge \
  cuda-toolkit=12.9.* \
  c-compiler=12.* cxx-compiler=12.* fortran-compiler=12.* \
  openmpi \
  cmake ninja fftw \
  openmm-torch pandas scipy pdoc

# Infiniband configuration
echo "pml = ucx"  >> ${CONDA_PREFIX}/etc/openmpi-mca-params.conf
echo "osc = ucx"  >> ${CONDA_PREFIX}/etc/openmpi-mca-params.conf

git clone brooks:/export/git/charmm
