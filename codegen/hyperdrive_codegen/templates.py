"""Template helpers."""

import os
from dataclasses import dataclass
from pathlib import Path

from jinja2 import Environment, Template

from hyperdrive_codegen.config import TemplateConfig
from hyperdrive_codegen.file import write_string_to_file


@dataclass
class TemplatePathInfo:
    path: str
    base_name: str
    folder: str


@dataclass
class TemplateInfo:
    template: Template
    path_info: TemplatePathInfo


deployer_templates = [
    TemplatePathInfo("deployers/HyperdriveCoreDeployer.sol.jinja", "HyperdriveCoreDeployer.sol", "deployers"),
    TemplatePathInfo("deployers/HyperdriveDeployerCoordinator.sol.jinja", "HyperdriveDeployerCoordinator", "deployers"),
    TemplatePathInfo("deployers/Target0Deployer.sol.jinja", "Target0Deployer", "deployers"),
    TemplatePathInfo("deployers/Target1Deployer.sol.jinja", "Target1Deployer", "deployers"),
    TemplatePathInfo("deployers/Target2Deployer.sol.jinja", "Target2Deployer", "deployers"),
    TemplatePathInfo("deployers/Target3Deployer.sol.jinja", "Target3Deployer", "deployers"),
    TemplatePathInfo("deployers/Target4Deployer.sol.jinja", "Target4Deployer", "deployers"),
]

instance_templates = [
    TemplatePathInfo("instances/Base.sol.jinja", "Base", "instances"),
    TemplatePathInfo("instances/Hyperdrive.sol.jinja", "Hyperdrive", "instances"),
    TemplatePathInfo("instances/Target0.sol.jinja", "Target0", "instances"),
    TemplatePathInfo("instances/Target1.sol.jinja", "Target1", "instances"),
    TemplatePathInfo("instances/Target2.sol.jinja", "Target2", "instances"),
    TemplatePathInfo("instances/Target3.sol.jinja", "Target3", "instances"),
    TemplatePathInfo("instances/Target4.sol.jinja", "Target4", "instances"),
]


def get_templates(env: Environment) -> list[TemplateInfo]:
    """Returns a list of template files for generating customized Hyperdrive instances.

    Parameters
    ----------
    env : Environment
        A jinja2 environment that is informed where the templates/ directory is.

    Returns
    -------
    list[Template]
        The list of jinja2 templates.
    """

    # Gather the template file strings and return a list of TemplateInfo's.
    path_infos = deployer_templates + instance_templates
    return [TemplateInfo(template=env.get_template(path_info.path), path_info=path_info) for path_info in path_infos]


@dataclass
class FileInfo:
    template: TemplateInfo
    rendered_code: str


def write_templates_to_files(templates: list[TemplateInfo], output_path: Path, template_config: TemplateConfig):
    for template in templates:
        # Get the file information and rendered code.
        file_info = FileInfo(template, rendered_code=template.template.render(template_config.model_dump()))

        # Get the contract file path.
        contract_file_name = f"{template_config.name.capitalized}{file_info.template.path_info.base_name}.sol"
        contract_file_path = Path(
            os.path.join(
                output_path, file_info.template.path_info.folder, template_config.name.lowercase, contract_file_name
            )
        )

        # Write the rendered code to file.
        write_string_to_file(contract_file_path, file_info.rendered_code)
