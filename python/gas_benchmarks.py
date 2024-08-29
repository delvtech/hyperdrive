import subprocess
import sys
import json

OUTPUT_PATH = sys.argv[1]

CONTRACT_NAME = "contracts/test/MockHyperdrive.sol:MockHyperdrive"
FUNCTION_NAMES = [
    "initialize",
    "addLiquidity",
    "removeLiquidity",
    "redeemWithdrawalShares",
    "openLong",
    "closeLong",
    "openShort",
    "closeShort",
    "checkpoint",
]

# HACK: We have to ignore the Chainlink instance test and the combinatorial test
# since these tests fail during gas benchmarking.
#
# Run the Solidity tests and write the test name and the gas used to a markdown table.
try:
    test_output = subprocess.check_output('FOUNDRY_FUZZ_RUNS=100 forge test --no-match-path \'test/instances/*\' --no-match-contract \'MultiToken__transferFrom\' --gas-report', shell=True).decode()
except subprocess.CalledProcessError as e:
    print(e.output)
    exit(1)
capture = []
found_contract = ""
found_report = False
for line in test_output.split("\n"):
    if not found_contract and CONTRACT_NAME in line:
        found_contract = True
    if found_contract and not found_report and "Function Name" in line:
        found_report = True
    elif found_report and len(line) > 0:
        cols = line.split("|")
        function_name = cols[1].strip()
        if function_name in FUNCTION_NAMES:
            capture += [
                {
                    "name": f"{cols[1].strip()}: min",
                    "value": cols[2].strip(),
                    "unit": "gas",
                }
            ]
            capture += [
                {
                    "name": f"{cols[1].strip()}: avg",
                    "value": cols[3].strip(),
                    "unit": "gas",
                }
            ]
            capture += [
                {
                    "name": f"{cols[1].strip()}: max",
                    "value": cols[5].strip(),
                    "unit": "gas",
                }
            ]
    elif found_report:
        break

with open(OUTPUT_PATH, "w") as f:
    json.dump(capture, f)
