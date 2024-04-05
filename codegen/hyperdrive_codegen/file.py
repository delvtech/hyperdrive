"""Utilities for working with files."""

import os
import shutil
from pathlib import Path


def write_string_to_file(path: str | os.PathLike, code: str) -> None:
    """Writes a string to a file.

    Parameters
    ----------
    path : str | os.PathLike
        The location of the output file.
    code : str
        The code to be written, as a single string.
    """
    with open(path, "w", encoding="utf-8") as output_file:
        output_file.write(code)


def get_output_folder_structure(lowercase_name: str) -> dict:
    """Returns a dictionary representation of the output folder structure.

    Parameters
    ----------
    lowercase_name: str
        The name of the protocol we are generating boilerplate integration code for.  Should be in all lowercase letters.

    Returns
    -------
    dict
    """
    return {"deployers": {lowercase_name: {}}, "instances": {lowercase_name: {}}, "interfaces": {}}


def setup_directory(base_path: Path | str, structure: dict, clear_existing: bool = False) -> None:
    """Recursively sets up a directory tree based on a given structure. Existing directories can be optionally cleared.

    Parameters
    ----------
    base_path : Path
        The base path where the directory tree starts.
    structure : dict
        A nested dictionary representing the directory structure to be created. Each key is a directory name with its value being another dictionary for subdirectories.
    clear_existing : bool, optional
        Whether to clear existing directories before setting up the new structure. Defaults to False.
    """
    base_path = Path(base_path)
    if clear_existing and base_path.exists():
        shutil.rmtree(base_path)
    base_path.mkdir(parents=True, exist_ok=True)

    for name, sub_structure in structure.items():
        sub_path = base_path / name
        if clear_existing and sub_path.exists():
            shutil.rmtree(sub_path)
        sub_path.mkdir(exist_ok=True)

        if isinstance(sub_structure, dict):
            # Recursively set up subdirectories
            setup_directory(sub_path, sub_structure, clear_existing)
