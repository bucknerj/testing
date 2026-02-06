#!/bin/bash

declare -a tests=(
  gamus
  gpu
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

declare -A tasks=(
  [gamus]=1
  [gpu]=1
  [gpu2]=2
  [lite]=1
  [ljpme]=2
  [misc]=2
  [misc2]=2
  [mndo97]=1
  [sccdftb]=1
  [squantm]=1
  [stringm]=8
  [tamd]=1
)

if [[ $# -eq 1 ]]; then
  echo "test $1 selected"
  test_name=$1
  ntasks=${tasks[$test_name]}
  ncpus=1
  ngpus=2
  if [[ $ntasks -eq 2 ]]; then
    ncpus=2
    ngpus=2
  fi
  args="M $ntasks X $ncpus cmake output"
  sbatch --job-name="$test_name-test" \
         --ntasks-per-node="$ntasks" --cpus-per-task="$ncpus" \
         --gres=gpu:$ngpus \
         --export=test_name="$test_name",test_args="$args" \
         -o "install-$test_name/test/%x-%j.out" \
         "test.bash"
  exit 0
fi

for test_name in "${tests[@]}"; do
  ntasks=${tasks[$test_name]}
  ncpus=1
  ngpus=2
  if [[ $ntasks -eq 2 ]]; then
    ncpus=2
    ngpus=2
  fi
  args="M $ntasks X $ncpus cmake output"
  sbatch --job-name="$test_name-test" \
         --ntasks-per-node="$ntasks" --cpus-per-task="$ncpus" \
         --gres=gpu:$ngpus \
         --export=test_name="$test_name",test_args="$args" \
         -o "install-$test_name/test/%x-%j.out" \
         "test.bash"
done
