"""Main entrypoint for hyperdrive-codegen tool."""

import argparse
import sys
from typing import NamedTuple, Sequence

from hyperdrive_codegen.codegen import codegen


def main(argv: Sequence[str] | None = None) -> None:
    """Main entrypoint for the hyperdrive-codegen tool.  Handles command-line arguments and calling codegen().

    Parameters
    ----------
    argv : Sequence[str] | None, optional
        Command line arguments
    """
    config_file_path, output_dir = parse_arguments(argv)
    codegen(config_file_path, output_dir)


class Args(NamedTuple):
    """Command line arguments for pypechain."""

    config_file_path: str
    output_dir: str


def namespace_to_args(namespace: argparse.Namespace) -> Args:
    """Converts argprase.Namespace to Args."""
    return Args(
        config_file_path=namespace.config,
        output_dir=namespace.out,
    )


def parse_arguments(argv: Sequence[str] | None = None) -> Args:
    """Parses input arguments"""
    parser = argparse.ArgumentParser(description="Generates class files for a given abi.")
    parser.add_argument(
        "--config",
        help="Path to the config yaml file.",
    )

    parser.add_argument(
        "--out",
        default="./out",
        help="Path to the directory where files will be generated. Defaults to out/.",
    )

    # Use system arguments if none were passed
    if argv is None:
        argv = sys.argv

    # If no arguments were passed, display the help message and exit
    if len(argv) == 1:
        parser.print_help(sys.stderr)
        sys.exit(1)

    return namespace_to_args(parser.parse_args())


if __name__ == "__main__":
    main()
