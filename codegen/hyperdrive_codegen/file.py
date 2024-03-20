"""Utilities for working with files."""

import os


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
