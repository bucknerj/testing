#!/bin/bash

npass=0
nfail=0
for outfile in $(ls install-*/*.build-*.out); do
  status=PASS
  grep -q fail $outfile
  if [[ "$?" -eq "0" ]]; then
    status=FAIL
    nfail=$((nfail + 1))
  else
    npass=$((npass + 1))
  fi
  build_date=$(awk '/^BEGIN BUILD SCRIPT/ {
    print substr($0, 20);
    exit }' $outfile)
  build_name=$(awk '/^DETECTED: build name/ {
    start = index($0, "->");
    end = index($0, "<-");
    print substr($0, start + 2, end - start - 2);
    exit }' $outfile)
  echo "BUILD $build_name DATE $build_date FILE $outfile STATUS $status"
done

echo ""
echo "$npass PASSING BUILDS"
echo "$nfail FAILING BUILDS"
