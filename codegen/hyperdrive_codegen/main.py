"""Main entrypoint for hyperdrive-codegen tool."""

from hyperdrive_codegen.codegen import codegen


def main():
    """Main entrypoint for the hyperdrive-codegen tool.  Handles command-line arguments and calling codegen()."""

    codegen()


if __name__ == "__main__":
    main()
