#!/bin/bash
#SBATCH --time=4:00:00
#SBATCH -p gpu2080
#SBATCH --nodes=1

echo "BEGIN TEST SCRIPT $(date)"

echo "DETECTED: test name ->${test_name}<-"
echo "DETECTED: test args ->${test_args}<-"

module load anaconda/miniconda-latest
eval "$(conda shell.bash hook)"
conda activate "$HOME/testing/env/test"

pushd "$HOME/testing/install-$test_name/test"

if [[ "${test_name}" == "sccdftb" ]] && [[ ! -L "./sccdftb.dat" ]]; then
  ln -s "$HOME/testing/sccdftb_data/sccdftb.dat" sccdftb.dat
fi

/usr/bin/tcsh ./test.com ${test_args} | tee "test.log" || true

if [[ -d "./bench" ]]; then
  awk -f compare.awk -v verbose=1 -v tol=0.0001 output.rpt > compare.out
fi

echo "END TEST SCRIPT $(date)"
