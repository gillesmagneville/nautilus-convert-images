"""
Extension Nautilus pour nautilus-convert-images.

Ajoute une entrée « Convertir les images… » dans le menu contextuel de
Nautilus, sur une sélection de fichiers/dossiers ou sur le fond d'un
dossier. L'extension ne fait que collecter les chemins sélectionnés et
lancer l'interface graphique autonome (convert-images-gui) : toute la
détection de format et la conversion proprement dite se font dans ce
process séparé, pour ne jamais bloquer ni faire planter Nautilus.

Installation : ce fichier doit se trouver sous
/usr/share/nautilus-python/extensions/ (et non ~/.local/... ni
/usr/local/..., pour rester visible depuis le bac à sable de Nautilus).
"""

import subprocess
import tempfile

import gi

gi.require_version("Nautilus", "4.0")
gi.require_version("GObject", "2.0")

from gi.repository import GObject, Nautilus  # noqa: E402

GUI_BINARY = "/usr/bin/convert-images-gui"
MENU_LABEL = "Convertir les images…"
MENU_TIP = "Détecter et convertir les images (RAW, JPEG, PNG, TIFF, BMP, WebP)"


def _write_path_list(paths):
    """Écrit la liste de chemins dans un fichier temporaire (un par ligne)
    afin d'éviter toute limite de longueur de ligne de commande lors d'une
    sélection très large."""
    fd = tempfile.NamedTemporaryFile(
        mode="w", suffix=".convert-images-selection.txt", delete=False
    )
    for p in paths:
        fd.write(p + "\n")
    fd.close()
    return fd.name


def _launch_gui(paths):
    if not paths:
        return
    list_file = _write_path_list(paths)
    subprocess.Popen(
        [GUI_BINARY, "--input-list", list_file],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def _local_path(file_info):
    """Renvoie le chemin local d'un Nautilus.FileInfo, ou None s'il ne
    s'agit pas d'un fichier local (ex. emplacement distant non monté)."""
    location = file_info.get_location()
    if location is None:
        return None
    return location.get_path()


class ConvertImagesMenuProvider(GObject.GObject, Nautilus.MenuProvider):
    def __init__(self):
        super().__init__()

    def _make_item(self, paths):
        item = Nautilus.MenuItem(
            name="ConvertImages::Convert",
            label=MENU_LABEL,
            tip=MENU_TIP,
        )
        item.connect("activate", lambda _item: _launch_gui(paths))
        return item

    def get_file_items(self, files):
        # `files` : sélection de fichiers et/ou dossiers.
        paths = [p for p in (_local_path(f) for f in files) if p]
        if not paths:
            return []
        return [self._make_item(paths)]

    def get_background_items(self, current_folder):
        # Clic droit sur le fond d'un dossier (rien de sélectionné) :
        # propose de convertir les images du dossier courant.
        path = _local_path(current_folder)
        if not path:
            return []
        return [self._make_item([path])]
