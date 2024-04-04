"""Utilities for working with jinja."""

import os

from jinja2 import Environment, FileSystemLoader


def get_jinja_env() -> Environment:
    """Returns the jinja environment."""
    script_dir = os.path.dirname(os.path.abspath(__file__))

    # Construct the path to your templates directory.
    templates_dir = os.path.join(script_dir, "../templates")
    env = Environment(loader=FileSystemLoader(templates_dir))

    return env
