import re
import os
import json
import glob
from collections import defaultdict

# Patterns for file and header
pattern = 'install-*/test/output.rpt'
header_regex = re.compile(r'<\*\*\s*(\w+)\s*:\s*([\w\d_]+)\s*\*\*>\s*(.*)')
special_keywords = [
    'ABNORMAL TERMINATION',
    'NOT performed',
    'NO TERMINATION',
    'NOT found'
]

def is_diff_line_normal(line):
    if not line.strip().startswith(('< ', '> ')):
        return True
    if re.match(r'[<>] <p class="overflow-x-auto overflow-y-hidden whitespace-pre-wrap break-words"><math display="block" class="tml-display" style="display:block math;"><mrow><mi>.</mi><mo>∗</mo></mrow></math></p> SET OMP_NUM_THREADS=\d+', line.strip()):
        return True
    return False

def grep_output_file(build_name, test_name):
    # For each build's output, look up output/{test_name}.out
    path = f"install-{build_name}/test/output/{test_name}.out"
    if not os.path.exists(path):
        return "OUTPUT FILE NOT FOUND"
    with open(path) as f:
        content = f.read().lower()
        if "testcase result: pass" in content or "test ok" in content:
            return "PASSED"
        if "abnormal termination" in content:
            return "ABNORMAL TERMINATION"
        if ("testcase result: skip" in content) or ("test not performed" in content):
            return "SKIPPED"
        if "testcase result: fail" in content:
            return "TESTCASE RESULT: FAIL"
        if "termination" not in content:
            return "NO TERMINATION"
    return "OUTPUT OK"

def extract_elapsed_time(build_name, test_name):
    path = f"install-{build_name}/test/output/{test_name}.out"
    if not os.path.exists(path):
        return None
    elapsed_time = None
    with open(path) as f:
        for line in f:
            m = re.search(r"ELAPSED TIME:\s+([\d\.]+)\s+SECONDS", line)
            if m:
                elapsed_time = float(m.group(1))
    return elapsed_time

def process_test_block(build_name, test, block):
    test['status'] = 'PASSED'
    diff_lines = []
    for line in block:
        for kw in special_keywords:
            if kw in line:
                test['status'] = kw if kw != 'NOT found' else 'NO TERMINATION'
                if kw == 'NOT found':
                    test.setdefault('missing_files', []).append(line.strip())
        if re.match(r'^\d+c\d+$', line.strip()):
            diff_lines = []
        if line.strip().startswith('< ') or line.strip().startswith('> ') or line.strip() == '---':
            diff_lines.append(line.strip())
    if test['status'] == 'PASSED' and diff_lines:
        for diff_line in diff_lines:
            if not is_diff_line_normal(diff_line):
                test['status'] = 'FAILED'
                break

    output_status = grep_output_file(build_name, test['test_name'])
    test['output_status'] = output_status

    if test['status'] == 'FAILED' and output_status == "PASSED":
        test['status'] = "PASSED (output file)"
    elif test['status'] == 'PASSED':
        if output_status == "ABNORMAL TERMINATION":
            test['status'] = "ABNORMAL TERMINATION (output file)"
        elif output_status == "SKIPPED":
            test['status'] = "SKIPPED (output file)"
        elif output_status == "TESTCASE RESULT: FAIL":
            test['status'] = "FAILED (output file)"
        elif output_status == "NO TERMINATION":
            test['status'] = "NO TERMINATION (output file)"
    return test

def normalize_status(status):
    if "PASSED" in status:
        return "PASSED"
    if "SKIPPED" in status:
        return "SKIPPED"
    if "FAILED" in status:
        return "FAILED"
    return "ERROR"

# ----- PROCESS ALL MATCHING FILES -----
results = []
overall_counts = defaultdict(int)
suite_counts = defaultdict(lambda: defaultdict(int))
build_counts = defaultdict(lambda: defaultdict(int))

rpt_files = sorted(glob.glob(pattern))
for rpt_file in rpt_files:
    m = re.match(r'install-(.*)/test/output\.rpt', rpt_file)
    if not m:
        continue
    build_name = m.group(1)
    current_test = {}
    buffer = []
    with open(rpt_file) as f:
        lines = f.readlines()
    for line in lines:
        header_match = header_regex.match(line)
        if header_match:
            if current_test:
                current_test = process_test_block(build_name, current_test, buffer)
                results.append({**current_test, 'build_name': build_name})
                buffer = []
            current_test = {
                'suite': header_match.group(1),
                'test_name': header_match.group(2),
                'timestamp': header_match.group(3).strip(),
                'status': '',
                'missing_files': []
            }
        else:
            buffer.append(line)
    if current_test:
        current_test = process_test_block(build_name, current_test, buffer)
        results.append({**current_test, 'build_name': build_name})

# Sort results alphabetically by build_name, suite, test_name
results.sort(key=lambda test: (test['build_name'].lower(), test['suite'].lower(), test['test_name'].lower()))

detailed_results = []
for test in results:
    norm_status = normalize_status(test['status'])
    overall_counts[norm_status] += 1
    suite_counts[test['suite']][norm_status] += 1
    build_counts[test['build_name']][norm_status] += 1
    test_for_json = {k: v for k, v in test.items() if k in ['build_name', 'suite', 'test_name', 'timestamp', 'status', 'output_status', 'missing_files']}
    test_for_json['normalized_status'] = norm_status
    test_for_json['elapsed_time'] = extract_elapsed_time(test['build_name'], test['test_name'])
    detailed_results.append(test_for_json)

summary = {
    "overall": {k: overall_counts[k] for k in ['PASSED', 'FAILED', 'SKIPPED', 'ERROR']},
    "by_suite": {
        suite: {k: suite_counts[suite][k] for k in ['PASSED', 'FAILED', 'SKIPPED', 'ERROR']}
        for suite in sorted(suite_counts.keys())
    },
    "by_build": {
        build: {k: build_counts[build][k] for k in ['PASSED', 'FAILED', 'SKIPPED', 'ERROR']}
        for build in sorted(build_counts.keys())
    }
}

final_report = {
    "summary": summary,
    "results": detailed_results
}

print(json.dumps(final_report, indent=2))

# To save to file:
# with open("test_summary.json", "w") as outjson:
#     json.dump(final_report, outjson, indent=2)
