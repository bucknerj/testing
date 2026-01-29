#!/bin/bash

for outfile in $(ls slurm-*.out); do
  status=PASS
  grep -q fail $outfile
  if [[ "$?" -eq "0" ]]; then
    status=FAIL
  fi
  build_name=$(awk '/^DETECTED: build name/ {
    start = index($0, "->");
    end = index($0, "<-");
    print substr($0, start + 2, end - start - 2);
    exit }' $outfile)
  echo "BUILD $build_name FILE $outfile STATUS $status"
done
