# Python fuzzing for mint/burn

This directory details how to install and run fuzzing on hyperdrive with mint/burn.

## Installation

First, compile the solidity contracts and make python types locally via `make`.

Next, follow the prerequisites installation instructions of [agent0](https://github.com/delvtech/agent0/blob/main/INSTALL.md).
Then install [uv](https://github.com/astral-sh/uv) for package management. No need to clone the repo locally 
(unless developing on agent0).

From the base directory of the `hyperdrive` repo, set up a python virtual environment:

```
uv venv --python 3.10 .venv
source .venv/bin/activate
```

From here, you can install the generated python types and agent0 via:

```
uv pip install -r python-fuzz/requirements.txt
```

## Running fuzzing

To run fuzzing, simply run the `fuzz_mint_burn.py` script:

```
python fuzz_mint_burn.py
```



