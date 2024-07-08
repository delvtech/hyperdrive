"""Utilities for working with the template config file."""

from pathlib import Path

import yaml
from pydantic import BaseModel


class Name(BaseModel):
    """Holds different versions of the instance name."""

    capitalized: str
    uppercase: str
    lowercase: str
    camelcase: str


class Contract(BaseModel):

    payable: bool
    as_base_allowed: bool


class TemplateConfig(BaseModel):
    """Configuration parameters for the codegen templates."""

    name: Name

    contract: Contract


def get_template_config(config_file_path: str | Path) -> TemplateConfig:
    """Loads a yaml configuation file into a TemplateConfig model.  The
    TemplateConfig holds all the variables the jinja template files use.

    Parameters
    ----------
    config_file_path : str | Path
        The path to the yaml config.

    Returns
    -------
    TemplateConfig
        The template configuration.
    """

    # Load the raw configuration data.
    config_file_path = Path(config_file_path)
    with open(config_file_path, "r", encoding="utf-8") as file:
        config_data = yaml.safe_load(file)

    # Populate the configuration model and return the result.
    template_config = TemplateConfig(**config_data)
    return template_config
