#!/bin/bash

declare -a tests=(
  gamus
  gpu1
  gpu2 
  lite
  ljpme
  misc
  misc2
  mndo97
  sccdftb
  squantm
  stringm
  tamd
)

declare -A builds=(
  [gamus]=gamus
  [gpu1]=gpu
  [gpu2]=gpu
  [lite]=lite
  [ljpme]=ljpme
  [misc]=misc
  [misc2]=misc2
  [mndo97]=mndo97
  [sccdftb]=sccdftb
  [squantm]=squantm
  [stringm]=stringm
  [tamd]=tamd
)

declare -A test_args=(
  [gamus]=""
  [gpu1]=""
  [gpu2]="M 2 X 2"
  [lite]=""
  [ljpme]="M 2 X 2"
  [misc]="M 2 X 2"
  [misc2]="M 2 X 2"
  [mndo97]=""
  [sccdftb]=""
  [squantm]=""
  [stringm]="M 8 X 2"
  [tamd]=""
)

declare -A threads=(
  [gamus]=1
  [gpu1]=1
  [gpu2]=4
  [lite]=1
  [ljpme]=4
  [misc]=4
  [misc2]=4
  [mndo97]=1
  [sccdftb]=1
  [squantm]=1
  [stringm]=16
  [tamd]=1
)

if [[ $# -eq 1 ]]; then
  echo "test $1 selected"
  test_name=$1
  build_name=${builds[$test_name]}
  out_dir=output
  if [[ "${test_name}" == "gpu2" ]]; then
    out_dir=${out_dir}2
  fi
  bench_dir=""
  args="${test_args[$test_name]} cmake $out_dir $bench_dir"
  sbatch --job-name="$test_name-build" \
         --cpus-per-task=${threads[$test_name]} \
         --export=ALL,test_name="$test_name",test_args="$args",test_out_dir="$out_dir",test_bench_dir="${bench_dir}",build_name="${build_name}" \
         -o "install-$build_name/test/%x-%j.out" \
         "test.bash"
  exit 0
fi

for test_name in "${tests[@]}"; do
  build_name=${builds[$test_name]}
  out_dir=output
  if [[ "${test_name}" == "gpu2" ]]; then
    out_dir=${out_dir}2
  fi
  bench_dir=""
  args="${test_args[$test_name]} cmake $out_dir $bench_dir"
  sbatch --job-name="$test_name-build" \
         --cpus-per-task=${threads[$test_name]} \
         --export=ALL,test_name="$test_name",test_args="$args",test_out_dir="$out_dir",test_bench_dir="${bench_dir}",build_name="${build_name}" \
         -o "install-$build_name/test/%x-%j.out" \
         "test.bash"
done
