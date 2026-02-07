import json
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict

def main():
    # Usage: python json_to_xunit.py input.json [output.xml]
    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else None

    with open(input_file, "r") as f:
        data = json.load(f)

    test_suites = defaultdict(list)
    for test in data["results"]:
        # Grouping: use build_name and suite as suite identifier
        suite_id = f"{test['build_name']}.{test['suite']}"
        test_suites[suite_id].append(test)

    # Create root element
    testsuites_elem = ET.Element("testsuites")

    for suite_name, testcases in sorted(test_suites.items()):
        testsuite_elem = ET.SubElement(
            testsuites_elem,
            "testsuite",
            name=suite_name,
            tests=str(len(testcases)),
            failures=str(sum(1 for t in testcases if t["normalized_status"] == "FAILED")),
            errors=str(sum(1 for t in testcases if t["normalized_status"] == "ERROR")),
            skipped=str(sum(1 for t in testcases if t["normalized_status"] == "SKIPPED")),
            time=str(sum(t["elapsed_time"] or 0 for t in testcases))
        )

        for test in sorted(
            testcases, key=lambda t: (str(t["test_name"]).lower())
        ):
            testcase_elem = ET.SubElement(
                testsuite_elem,
                "testcase",
                classname=suite_name,
                name=test["test_name"],
                time=str(test["elapsed_time"] or 0),
                # Use timestamp if desired
            )

            # Add description as system-out (optional)
            system_out_elem = ET.SubElement(testcase_elem, "system-out")
            out_lines = [
                f"build: {test['build_name']}",
                f"suite: {test['suite']}",
                f"timestamp: {test['timestamp']}",
                f"status: {test['status']}",
                f"output_status: {test['output_status']}",
                f"elapsed_time: {test['elapsed_time']}",
            ]
            if test.get("missing_files"):
                out_lines.append("missing_files: " + ", ".join(test["missing_files"]))
            system_out_elem.text = "\n".join(out_lines)

            # Add failed/skipped/error elements if needed
            if test["normalized_status"] == "FAILED":
                failure_elem = ET.SubElement(testcase_elem, "failure", message=test["status"])
                failure_elem.text = test.get("output_status", "Test failed")
            elif test["normalized_status"] == "ERROR":
                error_elem = ET.SubElement(testcase_elem, "error", message=test["status"])
                error_elem.text = test.get("output_status", "Test error")
            elif test["normalized_status"] == "SKIPPED":
                skipped_elem = ET.SubElement(testcase_elem, "skipped")
                skipped_elem.text = test.get("output_status", "Test skipped")

    # Write XML output (prettified)
    xml_bytes = ET.tostring(testsuites_elem, encoding="utf-8")
    import xml.dom.minidom
    parsed_xml = xml.dom.minidom.parseString(xml_bytes)
    pretty_xml = parsed_xml.toprettyxml(indent="  ")

    if output_file:
        with open(output_file, "w") as outf:
            outf.write(pretty_xml)
    else:
        print(pretty_xml)

if __name__ == "__main__":
    main()

