#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""
Loads the INSTALLED Nautilus extension with the real Python bindings of
Nautilus (the distribution's nautilus-python package), simulates a right click on
a folder and checks the label of the menu entry.

    check_extension.py <expected-label>

The language is chosen with the LANGUAGE variable, set before the call.
Environment variable: EXTENSION (default: the file installed by the package).
"""

import importlib.util
import os
import sys

import gi
from gi.repository import Gio

EXTENSION = os.environ.get(
    "EXTENSION", "/usr/share/nautilus-python/extensions/convert_images_nautilus.py"
)


class FakeFileInfo:
    """Stands in for Nautilus.FileInfo: only get_location() is used."""

    def get_location(self):
        return Gio.File.new_for_path("/tmp")


def main():
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    expected = sys.argv[1]

    spec = importlib.util.spec_from_file_location("cie_extension", EXTENSION)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)  # fails here if the Nautilus bindings are missing

    provider = module.ConvertImagesMenuProvider()
    items = provider.get_file_items([FakeFileInfo()])
    if len(items) != 1:
        print(f"{len(items)} menu entry(ies) instead of one")
        return 1
    label = items[0].get_property("label")
    if label != expected:
        print(f"label {label!r} instead of {expected!r}")
        return 1
    background = provider.get_background_items(FakeFileInfo())
    if len(background) != 1:
        print(f"right click on the folder background: {len(background)} entry(ies) instead of one")
        return 1
    print(f"label {label!r}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
