import subprocess
import sys
import json

OUTPUT_PATH = sys.argv[1]

# Run the Solidity tests and write the test name and the gas used to a markdown table.
test_output = subprocess.check_output(["forge", "test"]).decode()
benchmark_captures = []
for line in test_output.split("\n"):
    if "gas:" in line:
        test_name = line.split("(")[0].split()[-1]
        gas_used = line.split(":")[-1].strip().split(")")[0]
        benchmark_captures += [{"name": test_name, "value": gas_used, "unit": "gas"}]

with open(OUTPUT_PATH, "w") as f:
    json.dump(benchmark_captures, f)
