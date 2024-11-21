import json
import multiprocessing
import subprocess
import sys

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

print("Starting gas benchmarks...")
# Run the Solidity tests and write the test name and the gas used to a json file.  The gas-report
# option outputs a gas summary for every contract that looks like this:
#
# | contracts/test/MockHyperdrive.sol:MockHyperdrive contract |                 |        |        |        |         |
# |-----------------------------------------------------------|-----------------|--------|--------|--------|---------|
# | Deployment Cost                                           | Deployment Size |        |        |        |         |
# | 19563789                                                  | 97621           |        |        |        |         |
# | Function Name                                             | min             | avg    | median | max    | # calls |
# | accrue                                                    | 43765           | 43792  | 43789  | 43801  | 108     |
# | balanceOf                                                 | 2640            | 2973   | 2640   | 4640   | 6       |
# | getCheckpointExposure                                     | 7121            | 7121   | 7121   | 7121   | 216     |
# | getPoolConfig                                             | 9814            | 16819  | 20314  | 22814  | 1548    |
# | getPoolInfo                                               | 15073           | 26402  | 31392  | 31412  | 671     |
# | initialize                                                | 355979          | 356037 | 356035 | 356107 | 228     |
# | openLong                                                  | 33370           | 170709 | 126607 | 286702 | 444     |
# | pause                                                     | 42450           | 42456  | 42456  | 42462  | 2       |
# | setLongExposure                                           | 43914           | 43914  | 43914  | 43914  | 1       |
# | setPauser                                                 | 25306           | 25306  | 25306  | 25306  | 12      |
#
# We are only interested in the MockHyperdrive contract and functions listed in FUNCTION_NAMES.
# We parse the output with the following steps:
# 1. Check for the contract name.
# 2. Check for the beginning of the gas report summary by looking for "Function Name".
# 3. Go line by line and capture the gas report for functions that we are interested in.
# 4. When we reach the end of the report, break out of the for-loop.
try:
    num_threads = multiprocessing.cpu_count()
    print(f"{num_threads=}")

    # HACK: We have to ignore certains tests that fail during gas benchmarking.
    SKIP_TESTS = [
        "test_zombie_interest_short_lp",
        "test_zombie_interest_long_lp",
        "test_zombie_long",
        "test_zombie_short",
        "test_zombie_long_short",
        "test_netting_fuzz",
        "test__updateLiquidity__extremeValues__fuzz",
        "test_short_below_minimum_share_reserves",
    ]
    process = subprocess.Popen(
        f"FOUNDRY_FUZZ_RUNS=100 forge test --no-match-path 'test/instances/*' --no-match-test '{','.join(SKIP_TESTS)}' --no-match-contract 'MultiToken__transferFrom' --jobs {num_threads} --gas-report",
        shell=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
    )
    capture = []
    found_contract: bool = False
    found_report: bool = False
    if process.stdout:
        # Read the output line by line
        for line in iter(process.stdout.readline, ""):
            print(line)
            # Split the line into columns which we can use to check if we are in the gas report summary.
            cols = [col.strip() for col in line.split("|") if col.strip() != ""]

            # Once we have found the contract look for the gas report summary.
            if not found_contract and CONTRACT_NAME in line and len(cols) > 0:
                found_contract = True

            # Once we have found the gas report summary, start capturing the gas report.
            if found_contract and not found_report and "Function Name" in line:
                found_report = True

            # Now, go line by line and capture the gas report for functions that we are interested in.
            elif found_report and len(line) > 0 and len(cols) == 6:
                function_name = cols[0]
                if function_name in FUNCTION_NAMES:
                    capture += [
                        {
                            "name": f"{cols[0]}: min",
                            "value": cols[1],
                            "unit": "gas",
                        }
                    ]
                    capture += [
                        {
                            "name": f"{cols[0]}: avg",
                            "value": cols[2],
                            "unit": "gas",
                        }
                    ]
                    capture += [
                        {
                            "name": f"{cols[0]}: max",
                            "value": cols[3],
                            "unit": "gas",
                        }
                    ]
            # When we reach the end of the report, break out of the for-loop.
            elif found_report:
                break

    # Wait for the process to finish.
    process.wait()
    if process.returncode != 0 and process.stderr:
        print(process.stderr.read())
        exit(1)

    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(capture, f)

except subprocess.CalledProcessError as e:
    print(e.output)
    exit(1)
