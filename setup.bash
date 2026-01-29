#!/bin/bash

module load anaconda/miniconda-latest
eval "$(conda shell.bash hook)"
conda create -p env/test
conda activate /home/bucknerj/testing/env/test
conda install -c conda-forge \
  openmm-torch cuda-toolkit cmake ninja fftw openmpi \
  c-compiler cxx-compiler fortran-compiler \
  pandas scipy pdoc

# Infiniband configuration
echo "pml = ucx"  >> ${CONDA_PREFIX}/etc/openmpi-mca-params.conf
echo "osc = ucx"  >> ${CONDA_PREFIX}/etc/openmpi-mca-params.conf

git clone brooks:/export/git/charmm

