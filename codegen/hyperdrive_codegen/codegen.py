"""The main script to generate hyperdrive integration boilerplate code."""

import os
from pathlib import Path

import yaml

from hyperdrive_codegen.config import TemplateConfig
from hyperdrive_codegen.file import write_string_to_file
from hyperdrive_codegen.jinja import get_jinja_env


def codegen(config_file_path: Path | str, output_dir: Path | str):
    """Main script to generate hyperdrive integration boilerplate code."""

    # load config file
    config_file_path = Path(config_file_path)
    with open(config_file_path, "r", encoding="utf-8") as file:
        config_data = yaml.safe_load(file)

    template_config = TemplateConfig(**config_data)

    # load template files
    env = get_jinja_env()
    core_deployer_template = env.get_template("deployers/HyperdriveCoreDeployer.sol.jinja")

    # generate the code
    rendered_code = core_deployer_template.render(name=template_config.name)

    # write to file
    output_path = Path(output_dir)
    contract_file_name = f"{template_config.name.capitalized}HyperdriveCoreDeployer.sol"
    contract_file_path = Path(os.path.join(output_path, contract_file_name))
    write_string_to_file(contract_file_path, rendered_code)
