"""Entry point for installing hyperdrive math python package"""
from setuptools import setup
from setuptools_rust import Binding, RustExtension

setup(
    name="hyperdrive_math_py",
    version="0.1.0",
    packages=["hyperdrive_math_py"],
    package_dir={"": "python"},
    rust_extensions=[
        RustExtension("hyperdrive_math_py", binding=Binding.PyO3),
        RustExtension("hyperdrive_math_py.HyperdriveState", binding=Binding.PyO3),
    ],
    # rust extensions are not zip safe, just like C-extensions.
    zip_safe=False,
)
