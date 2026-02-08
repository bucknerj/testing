import json
import sys
from collections import defaultdict

def main():
    # Usage: python json_to_md_problem_tests.py test_summary.json
    input_file = sys.argv[1]

    with open(input_file, "r") as f:
        data = json.load(f)

    # Organize tests: suite -> test_name -> list of (build_name, status, output_status)
    problem_tests = defaultdict(lambda: defaultdict(list))

    for test in data["results"]:
        norm_status = test["normalized_status"]
        if norm_status not in ("PASSED", "SKIPPED"):
            suite = test["suite"]
            test_name = test["test_name"]
            build_info = {
                "build_name": test["build_name"],
                "status": test["status"],
                "output_status": test.get("output_status", ""),
                "elapsed_time": test.get("elapsed_time", None)
            }
            problem_tests[suite][test_name].append(build_info)

    # Print Markdown
    print("# Problematic Tests\n")
    for suite in sorted(problem_tests):
        print(f"## Suite: `{suite}`")
        for test_name in sorted(problem_tests[suite]):
            builds = problem_tests[suite][test_name]
            print(f"- **Test:** `{test_name}`")
            for b in sorted(builds, key=lambda x: x["build_name"]):
                status_str = b["status"]
                output_status = b["output_status"]
                elapsed_time = b["elapsed_time"]
                elapsed_note = f" (_Elapsed Time_: {elapsed_time:.2f}s)" if isinstance(elapsed_time, float) else ""
                print(f"    - Build: `{b['build_name']}` — Status: *{status_str}*; Output: *{output_status}*{elapsed_note}")
        print("")  # Blank line for spacing

if __name__ == "__main__":
    main()
