import json
import sys
from collections import defaultdict


builds = [
    "gamus", "gpu", "gpu2", "lite", "ljpme", "misc", "misc2", "mndo97",
    "sccdftb", "squantm", "stringm", "tamd"
]
data = []

for bn in builds:
    with open(f"install-{bn}/test/results20260210_1216.json") as f:
        data += json.load(f)
  
bad_tests = [test for test in data
        if test['status'] not in ("PASSED", "SKIPPED")]

bad_tests.sort(key=lambda test:
        (test['build_name'], test['suite'], test['test_name']))

with open('bad_tests.json', 'w') as outfile:
 json.dump(bad_tests, outfile, indent=2)
