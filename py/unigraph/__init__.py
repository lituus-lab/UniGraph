# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""unigraph — Python binding over the UniGraph C library.

Exposes one concrete graph: int64 vertex labels, float64 edge weights (see
src/UniGraph/c_api.nim for why the full generic Nim API isn't C-ABI-shaped).
"""
from importlib.metadata import PackageNotFoundError, version as distribution_version

from ._core import Graph, version as _version_c

try:
    __version__ = distribution_version("lituus-unigraph")
except PackageNotFoundError:
    __version__ = _version_c().decode("ascii")

__all__ = ["Graph", "version"]


def version():
    """C library version string."""
    return _version_c().decode("ascii")
