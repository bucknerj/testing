#!/usr/bin/env python3

import subprocess
import sys
from pathlib import Path

tests = [
    "gamus", "gpu", "gpu2", "lite", "ljpme", "misc", "misc2", "mndo97",
    "sccdftb", "squantm", "stringm", "tamd"
]

tasks = {
    "gamus": 1,
    "gpu": 1,
    "gpu2": 2,
    "lite": 1,
    "ljpme": 2,
    "misc": 2,
    "misc2": 2,
    "mndo97": 1,
    "sccdftb": 1,
    "squantm": 1,
    "stringm": 8,
    "tamd": 1,
}

def submit_job(test_name):
    ntasks = tasks[test_name]
    ncpus = 1
    ngpus = 2
    if ntasks == 2:
        ncpus = 2
        ngpus = 2
    args = f"M {ntasks} X {ncpus} cmake output"
    outdir = Path(f"install-{test_name}/test")
    outdir.mkdir(parents=True, exist_ok=True)
    output_file = outdir / "%x-%j.out"

    sbatch_cmd = [
        "sbatch",
        f"--job-name={test_name}-test",
        f"--ntasks-per-node={ntasks}",
        f"--cpus-per-task={ncpus}",
        f"--gres=gpu:{ngpus}",
        f"--export=test_name={test_name},test_args={args}",
        f"-o", str(output_file),
        "test.bash"
    ]

    print(f"Submitting job for '{test_name}' with args: {args}")
    subprocess.run(sbatch_cmd, check=True)

def main():
    if len(sys.argv) == 2:
        test_name = sys.argv[1]
        if test_name not in tasks:
            print(f"Unknown test name: {test_name}")
            sys.exit(1)
        print(f"Test {test_name} selected")
        submit_job(test_name)
        sys.exit(0)

    for test_name in tests:
        submit_job(test_name)

if __name__ == "__main__":
    main()
