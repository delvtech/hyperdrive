"""Main entrypoint for hyperdrive-codegen tool."""

import os
from pathlib import Path

import yaml
from jinja2 import Environment, FileSystemLoader
from pydantic import BaseModel


def main():
    """Main entrypoint for the hyperdrive-codegen tool.  Handles command-line arguments and calling codegen()."""

    print("Welcome to Hyperdrive Codegen!")
    # Your code generation logic will go here.
    # For now, let's just print a message to the terminal.
    print("This tool generates boilerplate code for the Hyperdrive project using Jinja templates.")
    codegen()


class Name(BaseModel):
    """Holds different versions of the instance name."""

    capitalized: str
    lowercase: str
    camelcase: str


class TemplateConfig(BaseModel):
    """Configuration parameters for the codegen templates."""

    name: Name


def codegen():
    """Main script to generate hyperdrive integration boilerplate code."""

    # load config file
    config_file_path = Path("./example/config.yaml")
    with open(config_file_path, "r", encoding="utf-8") as file:
        config_data = yaml.safe_load(file)

    template_config = TemplateConfig(**config_data)

    # load template files
    env = get_jinja_env()
    core_deployer_template = env.get_template("deployers/HyperdriveCoreDeployer.sol.jinja")

    # generate the code
    rendered_code = core_deployer_template.render(name=template_config.name)

    # write to file
    output_path = Path("./example/out/deployers")
    contract_file_name = f"{template_config.name.capitalized}HyperdriveCoreDeployer.sol"
    contract_file_path = Path(os.path.join(output_path, contract_file_name))
    write_string_to_file(contract_file_path, rendered_code)


def get_jinja_env() -> Environment:
    """Returns the jinja environment."""
    script_dir = os.path.dirname(os.path.abspath(__file__))

    # Construct the path to your templates directory.
    templates_dir = os.path.join(script_dir, "../templates")
    env = Environment(loader=FileSystemLoader(templates_dir))

    return env


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


if __name__ == "__main__":
    main()
