"""
Nautilus extension for nautilus-convert-images.

Adds a "Convert images…" entry to the Nautilus context menu, on a
selection of files/folders or on the background of a folder. The
extension only collects the selected paths and launches the standalone
graphical interface (convert-images-gui): all the format detection and
the conversion proper happen in this separate process, so as to never
block or crash Nautilus.

Installation: this file must be located under
/usr/share/nautilus-python/extensions/ (and not ~/.local/... nor
/usr/local/..., to stay visible from Nautilus' sandbox).
"""

import gettext
import os
import subprocess
import tempfile

import gi

# Deliberately NO gi.require_version("Nautilus", ...): by the time this file
# runs, the host Nautilus process has already loaded the Nautilus typelib
# matching its own version (4.0, 4.1, ...). Pinning a precise version here
# fails depending on the machine: either it does not match the one already
# loaded by Nautilus itself ("already loaded with version X"), or it is
# simply not installed on this system ("not available for version X").
# GObject, on the other hand, has only one possible introspection version
# (2.0): pinning it poses no risk of conflict.
gi.require_version("GObject", "2.0")

from gi.repository import GObject, Nautilus  # noqa: E402

GUI_BINARY = "/usr/bin/convert-images-gui"

# Internationalization (gettext): source texts in English, language chosen
# from Nautilus' environment (LANGUAGE, LC_ALL, LC_MESSAGES, LANG),
# English if no translation exists. Same domain as the interface.
I18N_DOMAIN = "nautilus-convert-images"
LOCALE_DIR = os.environ.get("CONVERT_IMAGES_LOCALEDIR", "/usr/share/locale")
_ = gettext.translation(I18N_DOMAIN, localedir=LOCALE_DIR, fallback=True).gettext


def _write_path_list(paths):
    """Writes the list of paths to a temporary file (one per line)
    to avoid any command-line length limit with a very large
    selection."""
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
    """Returns the local path of a Nautilus.FileInfo, or None if it is
    not a local file (e.g. a remote location that is not mounted)."""
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
            label=_("Convert images…"),
            tip=_("Detect and convert images (RAW, JPEG, PNG, TIFF, BMP, WebP)"),
        )
        item.connect("activate", lambda _item: _launch_gui(paths))
        return item

    def get_file_items(self, files):
        # `files`: selection of files and/or folders.
        paths = [p for p in (_local_path(f) for f in files) if p]
        if not paths:
            return []
        return [self._make_item(paths)]

    def get_background_items(self, current_folder):
        # Right click on the background of a folder (nothing selected):
        # offers to convert the images of the current folder.
        path = _local_path(current_folder)
        if not path:
            return []
        return [self._make_item([path])]
