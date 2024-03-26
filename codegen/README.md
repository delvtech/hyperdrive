# Integrations Codegen Guide

To make integrating hyperdrive with other protocols easier, we've created tooling to generate most of the boilerplate code. This guide walks though how to install and run the codegen tools.

Here's a quick overview of the directory.

```
hyperdrive/
│
├── codegen/                # Codegen tool directory
│   ├── hyperdrive-codegen/ # Python package for the codegen tool
│   │   ├── __init__.py     # Makes hyperdrive-codegen a Python package
│   │   ├── main.py         # Entry point of the tool, handles command line arguments, calls codegen.py
|   |   ├── codegen.py      # Main script of the tool
│   │   └── ...             # Other Python modules and package data
│   │
│   ├── templates/          # Jinja templates directory
│   │   └── ...             # Template files
│   │
│   ├── example/            # An example result of the tool
│   │   └── config.yaml     # The template configuration file
│   │   └── out/            # The generated code
│   │
│   ├── pyproject.toml      # Configuration file for build system and dependencies
│   └── .venv/              # Virtual environment (excluded from version control)
│
├── contracts/              # Solidity contracts directory
│   └── ...                 # Solidity files
```

## Install

### 0. Install Python

You'll need to have python installed on your machine to use this tool. Installation varies by operatin system.

### 1. Install Pyenv

Follow [Pyenv install instructions](https://github.com/pyenv/pyenv#installation).

### 2. Set up virtual environment

You can use any environment, but we recommend [venv](https://docs.python.org/3/library/venv.html), which is part of the standard Python library.

From hyperdrive's root directory, run:

```bash
pip install --upgrade pip
pyenv install 3.10
pyenv local 3.10
python -m venv .venv
source .venv/bin/activate
```

### 4. Install dependencies

To install the dependencies:

```bash
pip install -e .
```

### 5. Check Installation

Verify that your package was installed correctly by running something like pip list. You should see hyperdrive-codegen listed as a package.

## Usage

If installation was successful, you should be able to run the command from the terminal:

```bash
hyperdrive-codegen
```
