"""Template helpers."""

import os
from dataclasses import dataclass
from pathlib import Path

from hyperdrive_codegen.config import TemplateConfig
from hyperdrive_codegen.file import write_string_to_file
from jinja2 import Environment, Template


@dataclass
class TemplatePathInfo:
    """Path and name information for the template."""

    path: str
    base_name: str
    folder: str


@dataclass
class TemplateInfo:
    """Contains a jinja template and path information."""

    template: Template
    path_info: TemplatePathInfo


@dataclass
class FileInfo:
    """Contains template information and the rendered code."""

    template: TemplateInfo
    rendered_code: str


deployer_templates = [
    TemplatePathInfo("deployers/HyperdriveCoreDeployer.sol.jinja", "HyperdriveCoreDeployer", "deployers"),
    TemplatePathInfo("deployers/HyperdriveDeployerCoordinator.sol.jinja", "HyperdriveDeployerCoordinator", "deployers"),
    TemplatePathInfo("deployers/Target0Deployer.sol.jinja", "Target0Deployer", "deployers"),
    TemplatePathInfo("deployers/Target1Deployer.sol.jinja", "Target1Deployer", "deployers"),
    TemplatePathInfo("deployers/Target2Deployer.sol.jinja", "Target2Deployer", "deployers"),
    TemplatePathInfo("deployers/Target3Deployer.sol.jinja", "Target3Deployer", "deployers"),
    TemplatePathInfo("deployers/Target4Deployer.sol.jinja", "Target4Deployer", "deployers"),
]

instance_templates = [
    TemplatePathInfo("instances/Base.sol.jinja", "Base", "instances"),
    TemplatePathInfo("instances/Conversions.sol.jinja", "Conversions", "instances"),
    TemplatePathInfo("instances/Hyperdrive.sol.jinja", "Hyperdrive", "instances"),
    TemplatePathInfo("instances/Target0.sol.jinja", "Target0", "instances"),
    TemplatePathInfo("instances/Target1.sol.jinja", "Target1", "instances"),
    TemplatePathInfo("instances/Target2.sol.jinja", "Target2", "instances"),
    TemplatePathInfo("instances/Target3.sol.jinja", "Target3", "instances"),
    TemplatePathInfo("instances/Target4.sol.jinja", "Target4", "instances"),
]

interface_templates = [
    TemplatePathInfo("interfaces/IHyperdrive.sol.jinja", "Hyperdrive", "interfaces"),
    TemplatePathInfo("interfaces/IYieldSource.sol.jinja", "", "interfaces"),
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
    path_infos = deployer_templates + instance_templates + interface_templates
    return [TemplateInfo(template=env.get_template(path_info.path), path_info=path_info) for path_info in path_infos]


def write_templates_to_files(templates: list[TemplateInfo], output_path: Path, template_config: TemplateConfig):
    """Writes a given list of templates to file.

    Parameters
    ----------
    templates : list[TemplateInfo]
        Template information containing path information and the rendered code.
    output_path : Path
        The directory to write files to.
    template_config : TemplateConfig
        Template configuration, has all the variables the jinja templates use.
    """

    for template in templates:
        # Get the file information and rendered code.
        file_info = FileInfo(template, rendered_code=template.template.render(template_config.model_dump()))

        # Get the contract file name
        contract_file_name = f"{template_config.name.capitalized}{file_info.template.path_info.base_name}.sol"

        # Prepend 'I' to the file name if it is an interface file
        is_interface_file = file_info.template.path_info.folder == "interfaces"
        if is_interface_file:
            contract_file_name = "I" + contract_file_name
            # NOTE: don't place interface files in a subfolder
            contract_file_path = Path(
                os.path.join(output_path, file_info.template.path_info.folder, contract_file_name)
            )
        else:
            contract_file_path = Path(
                os.path.join(
                    output_path, file_info.template.path_info.folder, template_config.name.lowercase, contract_file_name
                )
            )

        # Write the rendered code to file.
        write_string_to_file(contract_file_path, file_info.rendered_code)
