#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""
Charge l'extension Nautilus INSTALLÉE avec les vraies liaisons Python de
Nautilus (paquet nautilus-python de la distribution), simule un clic droit sur
un dossier et vérifie le libellé de l'entrée de menu.

    check_extension.py <libellé-attendu>

La langue se choisit avec la variable LANGUAGE, définie avant l'appel.
Variable d'environnement : EXTENSION (défaut : le fichier installé par le paquet).
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
    """Fait office de Nautilus.FileInfo : seule get_location() est utilisée."""

    def get_location(self):
        return Gio.File.new_for_path("/tmp")


def main():
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    expected = sys.argv[1]

    spec = importlib.util.spec_from_file_location("cie_extension", EXTENSION)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)  # échoue ici si les liaisons Nautilus manquent

    provider = module.ConvertImagesMenuProvider()
    items = provider.get_file_items([FakeFileInfo()])
    if len(items) != 1:
        print(f"{len(items)} entrée(s) de menu au lieu d'une")
        return 1
    label = items[0].get_property("label")
    if label != expected:
        print(f"libellé {label!r} au lieu de {expected!r}")
        return 1
    background = provider.get_background_items(FakeFileInfo())
    if len(background) != 1:
        print(f"clic droit sur le fond d'un dossier : {len(background)} entrée(s) au lieu d'une")
        return 1
    print(f"libellé {label!r}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
