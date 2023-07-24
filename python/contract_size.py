import sys
import json
from os import listdir
from os.path import join, isdir, basename


class bcolors:
    HEADER = "\033[95m"
    OKBLUE = "\033[94m"
    OKCYAN = "\033[96m"
    OKGREEN = "\033[92m"
    WARNING = "\033[93m"
    FAIL = "\033[91m"
    ENDC = "\033[0m"
    BOLD = "\033[1m"
    UNDERLINE = "\033[4m"


def get_artifact_paths(out_path):
    artifact_paths = []
    for path in listdir(out_path):
        absolute_path = join(out_path, path)
        if isdir(absolute_path):
            artifact_paths += get_artifact_paths(absolute_path)
        else:
            artifact_paths += [absolute_path]
    return artifact_paths


# Get the file in which the compiled contract resides. This is useful for
# filtering for contracts
def get_compilation_target(artifact):
    if not "metadata" in artifact:
        return None
    return list(artifact["metadata"]["settings"]["compilationTarget"].keys())[0]


# We only check the code size for contracts in "contracts/src" and a few of the
# mock contracts that we may need to deploy.
def should_check_code_size(artifact):
    compilation_target = get_compilation_target(artifact)
    if not compilation_target:
        return False
    return "contracts/src/" in compilation_target


ARTIFACTS_PATH = sys.argv[1]

info = {}
for artifact_path in get_artifact_paths(ARTIFACTS_PATH):
    with open(artifact_path, "r") as f:
        contract_name = basename(artifact_path).split(".")[0]
        artifact = json.load(f)
        if should_check_code_size(artifact):
            info[contract_name] = {}
            info[contract_name]["bytecode_size"] = (
                len(artifact["bytecode"]["object"][2:]) / 2
            )

print("|             Contract              | Bytecode Size |     Margin    |")
print("| --------------------------------- | ------------- | ------------- |")

failure = False
for contract in sorted(info):
    bytecode_size = info[contract]["bytecode_size"]
    margin = 24 * 1024 - bytecode_size

    # If the margin is greater than 3 kb, we don't use a terminal color. If the
    # margin is less than 3 kb but the codesize is still acceptable, the color
    # is WARNING. Otherwise, the color is FAIL.
    if margin >= 3 * 1024:
        color = ""  # bcolors.OKBLUE
    elif margin >= 0:
        color = bcolors.WARNING
    else:
        failure = True
        color = bcolors.FAIL

    print(
        f"| {contract:<33} | {bytecode_size:>13} | {color}{margin:>13}{bcolors.ENDC} |"
    )

if failure:
    exit(1)

exit(0)
