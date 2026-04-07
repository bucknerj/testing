#!/bin/bash

for build_dir in $(ls -d install-*); do
  pushd "$build_dir/test"
  if [[ -d "old" ]]; then
    rm -rf "old"
  fi
  if [[ -f "old.tgz" ]]; then
    rm "old.tgz"
  fi
  mkdir "old"
  if [[ -d "output" ]]; then
    cp -r "output" "old/"
    rm -rf "output"
  fi
  if [[ -f "output.rpt" ]]; then
    cp "output.rpt" "old/"
    rm "output.rpt"
  fi
  for fn in $(ls *.out *.json *.log); do
    cp "$fn" old/
    rm "$fn"
  done
  if [[ -d old ]]; then
    tar czf old.tgz old
    rm -rf old
  fi
  popd
done
