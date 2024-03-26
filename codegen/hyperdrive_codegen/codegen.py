"""The main script to generate hyperdrive integration boilerplate code."""

from pathlib import Path

from jinja2 import Environment

from hyperdrive_codegen.config import get_template_config
from hyperdrive_codegen.file import get_output_folder_structure, setup_directory
from hyperdrive_codegen.jinja import get_jinja_env
from hyperdrive_codegen.templates import get_templates, write_templates_to_files


def codegen(config_file_path: Path | str, output_dir: Path | str, clear_existing: bool = False):
    """Main script to generate hyperdrive integration boilerplate code."""

    # Load the configuration file that has all the variables used in the
    # template files.
    template_config = get_template_config(config_file_path)

    # Get the templates to render.
    env: Environment = get_jinja_env()
    templates = get_templates(env)

    # Setup the output directory.
    folder_structure = get_output_folder_structure(template_config.name.lowercase)
    output_path = Path(output_dir)
    setup_directory(output_path, folder_structure, clear_existing)

    # Write the templates to files.
    write_templates_to_files(templates, output_path, template_config)
