#!/bin/bash
#SBATCH --time=4:00:00
#SBATCH -p ada5000
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --gres=gpu:1

echo "BEGIN TEST SCRIPT $(date)"

echo "DETECTED: test name ->${test_name}<-"
echo "DETECTED: test args ->${test_args}<-"
echo "DETECTED: test out dir ->${test_out_dir}<-"
echo "DETECTED: test bench dir ->${test_bench_dir}<-"
echo "DETECTED: build name ->${build_name}<-"

module load anaconda/miniconda-latest
eval "$(conda shell.bash hook)"
conda activate "$HOME/testing/env/test"

pushd "$HOME/testing/install-$build_name/test"

if [[ "${test_name}" == "sccdftb" ]]; then
  ln -sf "$HOME/testing/sccdftb_data/sccdftb.dat" sccdftb.dat
fi

sed '/limit filesize/d' ./test.com > test2.com
/usr/bin/tcsh ./test2.com ${test_args} | tee "test.log" || true

if [[ -d "${test_bench_dir}" ]]; then
  CMPDIR="${test_bench_dir}" ../tool/Compare "${test_out_dir}" " " \
        | tee compare.log
fi
