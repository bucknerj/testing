import glob
import re
import os
import json
import subprocess
import logging
from mpi4py import MPI
import click

def setup_logging(logfile=None):
    logger = logging.getLogger("score")
    logger.setLevel(logging.INFO)
    handler = logging.StreamHandler() if logfile is None else logging.FileHandler(logfile)
    formatter = logging.Formatter('[%(asctime)s] %(levelname)s: %(message)s')
    handler.setFormatter(formatter)
    logger.handlers = []  # Remove any default handlers
    logger.addHandler(handler)
    return logger

def grep_output_file(build_name, test_name):
    path = f"install-{build_name}/test/output/{test_name}.out"
    if not os.path.exists(path):
        return "OUTPUT FILE NOT FOUND"
    patterns = [
        ("TESTCASE RESULT: PASS", "PASSED", False),
        ("Test Ok", "PASSED", False),
        ("TESTCASE RESULT: FAIL", "FAILED", False),
        ("ABNORMAL TERMINATION", "ABNORMAL TERMINATION", False),
        ("TESTCASE RESULT: SKIP", "SKIPPED", False),
        ("test not performed", "SKIPPED", False),
        ("TERMINATION", "NO TERMINATION", True), # -L, i.e. NOT found
    ]
    for pattern, status, negate in patterns:
        try:
            if negate:
                result = subprocess.run(["grep", "-L", pattern, path], stdout=subprocess.PIPE, text=True)
                if result.stdout.strip():
                    return status
            else:
                result = subprocess.run(["grep", "-i", pattern, path], stdout=subprocess.PIPE, text=True)
                if result.returncode == 0:
                    return status
        except Exception:
            pass
    return "OUTPUT OK"

def extract_elapsed_time(build_name, test_name):
    path = f"install-{build_name}/test/output/{test_name}.out"
    if not os.path.exists(path):
        return None
    try:
        result = subprocess.run(["grep", "ELAPSED TIME:", path], stdout=subprocess.PIPE, text=True)
        match = re.search(r"ELAPSED TIME:\s+([\d\.]+)\s+SECONDS", result.stdout)
        if match:
            return float(match.group(1))
    except Exception:
        pass
    return None

def get_all_build_names():
    rpt_files = glob.glob('install-*/test/output.rpt')
    build_names = []
    for rpt in rpt_files:
        m = re.match(r'install-(.*)/test/output\.rpt', rpt)
        if m:
            build_names.append(m.group(1))
    return build_names

def normalize_status(status):
    if status.startswith("PASSED"):
        return "PASSED"
    if status.startswith("SKIPPED"):
        return "SKIPPED"
    if status.startswith("FAILED"):
        return "FAILED"
    if status.startswith("ABNORMAL TERMINATION"):
        return "ERROR"
    if status.startswith("NO TERMINATION"):
        return "ERROR"
    if status.startswith("OUTPUT FILE NOT FOUND"):
        return "ERROR"
    return "ERROR"

@click.command()
@click.argument('build_names', nargs=-1)
@click.option('-o', '--output', type=click.Path(writable=True), help='File to write JSON output.')
@click.option('--log', type=click.Path(writable=True), help='File to write log output. If not given, logs go to stdout.')
def score(build_names, output, log):
    """
    score.py: Process build test logs using MPI and output JSON summary.

    Optionally specify build names as space-delimited arguments.
    If none are given, all builds found under install-*/test/output.rpt will be processed.

    -o/--output: Output JSON to file.
    --log: Write log messages to file instead of stdout.
    """
    logger = setup_logging(log if output else None)  # Log to file if --log used, else to stdout if --output

    comm = MPI.COMM_WORLD
    rank = comm.Get_rank()
    size = comm.Get_size()

    if output:
        # Only rank 0 will write output/log, but all ranks log their own progress if desired
        logger.info(f"Rank {rank}: Starting score.py with output file '{output}' and log '{log or 'stdout'}'.")

    # If no build_names provided, discover all
    if not build_names:
        build_names = get_all_build_names()
        if output:
            logger.info(f"Rank {rank}: No build names given, found {len(build_names)} builds to process.")
    else:
        build_names = sorted(set(build_names))
        if output:
            logger.info(f"Rank {rank}: Build names given: {build_names}")

    # Filter for actually existing builds
    build_names_actual = []
    for bn in build_names:
        rpt_file = f"install-{bn}/test/output.rpt"
        if os.path.exists(rpt_file):
            build_names_actual.append(bn)
        elif output:
            logger.warning(f"Rank {rank}: Build '{bn}' has no output.rpt, skipping.")

    # Partition builds to processes
    my_builds = build_names_actual[rank::size]
    if output:
        logger.info(f"Rank {rank}: Assigned builds: {my_builds}")

    header_regex = re.compile(r'<\*\*\s*(\w+)\s*:\s*([\w\d_]+)\s*\*\*>\s*(.*)')

    results = []
    for build_name in my_builds:
        rpt_file = f"install-{build_name}/test/output.rpt"
        if output:
            logger.info(f"Rank {rank}: Parsing '{rpt_file}'")
        if not os.path.exists(rpt_file):
            continue
        with open(rpt_file) as f:
            lines = f.readlines()
        current_test = {}
        buffer = []
        for line in lines:
            header_match = header_regex.match(line)
            if header_match:
                if current_test:
                    test_name = current_test['test_name']
                    output_status = grep_output_file(build_name, test_name)
                    elapsed_time = extract_elapsed_time(build_name, test_name)
                    status = normalize_status(output_status)
                    results.append({
                        'build_name': build_name,
                        'suite': current_test['suite'],
                        'test_name': test_name,
                        'timestamp': current_test['timestamp'],
                        'status': status,
                        'output_status': output_status,
                        'elapsed_time': elapsed_time,
                    })
                    if output:
                        logger.info(f"Rank {rank}: Finished test '{test_name}' in suite '{current_test['suite']}' with status '{status}'.")
                    buffer = []
                current_test = {
                    'suite': header_match.group(1),
                    'test_name': header_match.group(2),
                    'timestamp': header_match.group(3).strip(),
                }
            else:
                buffer.append(line)
        if current_test:
            test_name = current_test['test_name']
            output_status = grep_output_file(build_name, test_name)
            elapsed_time = extract_elapsed_time(build_name, test_name)
            status = normalize_status(output_status)
            results.append({
                'build_name': build_name,
                'suite': current_test['suite'],
                'test_name': test_name,
                'timestamp': current_test['timestamp'],
                'status': status,
                'output_status': output_status,
                'elapsed_time': elapsed_time,
            })
            if output:
                logger.info(f"Rank {rank}: Finished test '{test_name}' in suite '{current_test['suite']}' with status '{status}'.")

    all_results = comm.gather(results, root=0)

    if rank == 0:
        final_results = [item for sublist in all_results for item in sublist]
        final_results.sort(key=lambda test: (test['build_name'].lower(), test['suite'].lower(), test['test_name'].lower()))
        if output:
            logger.info(f"Rank 0: Writing JSON output to '{output}'")
            with open(output, "w") as outjson:
                json.dump(final_results, outjson, indent=2)
        else:
            print(json.dumps(final_results, indent=2))

if __name__ == "__main__":
    score()
