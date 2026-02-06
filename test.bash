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

if [[ ! -f "./test2.com" ]]; then
  sed '/limit filesize/d' ./test.com > test2.com
fi
/usr/bin/tcsh ./test2.com ${test_args} | tee "test.log" || true

if [[ -d "./bench" ]]; then
  CMPDIR="${test_bench_dir}" ../tool/Compare "${test_out_dir}" " " \
        | tee compare.log
fi

echo "END TEST SCRIPT $(date)"
