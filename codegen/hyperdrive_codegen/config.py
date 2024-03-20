"""Utilities for working with the template config file."""

from pydantic import BaseModel


class Name(BaseModel):
    """Holds different versions of the instance name."""

    capitalized: str
    lowercase: str
    camelcase: str


class TemplateConfig(BaseModel):
    """Configuration parameters for the codegen templates."""

    name: Name
