#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""
Vérifie, dans la vraie interface (GTK4), qu'une ligne très longue du journal
passe à la ligne au lieu de déborder de la fenêtre. Imprime en JSON les
mesures prises une fois la fenêtre affichée.

Il faut un écran : dans un environnement sans session graphique, lancer via

    xvfb-run -a -s "-screen 0 900x800x24" python3 tests/gui_log_wrap.py <dossier-d-images>

Variable d'environnement utile (développement et tests) :
    CONVERT_IMAGES_ENGINE     chemin du binaire convert-images-engine
"""

import importlib.machinery
import importlib.util
import json
import os
import sys
from pathlib import Path

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import GLib, Gtk  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
GUI_PATH = ROOT / "nautilus-extension" / "convert-images-gui"
WATCHDOG_SECONDS = 40

# Un chemin sans espace (cas réel : aucun point de coupure naturel) suivi d'un
# message long, puis une ligne courte qui doit rester intacte.
LONG_PATH = "/home/user/Photos/" + "tres_long_nom_de_dossier_" * 12 + "IMG_0001.CR2"
LONG_LINE = f"[ERROR] {LONG_PATH}: " + "failed to decode the image data " * 6 + "\n"
SHORT_LINE = "[OK] a.jpg → b.png\n"


def load_gui():
    loader = importlib.machinery.SourceFileLoader("convert_images_gui", str(GUI_PATH))
    spec = importlib.util.spec_from_loader("convert_images_gui", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def main():
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2

    gui = load_gui()
    result = {"stage": "start"}
    state = {"win": None}

    class App(gui.ConvertImagesApp):
        def do_activate(self):
            super().do_activate()
            state["win"] = self.get_active_window()

    app = App([sys.argv[1]])

    def wait_for_window():
        win = state["win"]
        if win is None or not win.options_box.get_visible():
            return True
        win.log_scroller.set_visible(True)
        for line in (SHORT_LINE, LONG_LINE, SHORT_LINE):
            win._append_log(line)
        GLib.timeout_add(600, measure)
        return False

    def measure():
        # Une exception dans un rappel GLib serait avalée : on la consigne pour
        # que l'échec du test dise pourquoi au lieu d'attendre le délai de sécurité.
        try:
            win = state["win"]
            hadj = win.log_scroller.get_hadjustment()
            result.update(
                stage="measured",
                wrap_none=win.log_view.get_wrap_mode() == Gtk.WrapMode.NONE,
                scroller_width=win.log_scroller.get_width(),
                view_width=win.log_view.get_width(),
                hscroll_upper=hadj.get_upper(),
                hscroll_page=hadj.get_page_size(),
            )
        except Exception as e:  # noqa: BLE001
            result.update(stage="error", error=f"{type(e).__name__}: {e}")
        app.quit()
        return False

    def watchdog():
        result["stage"] += " (TIMEOUT)"
        print(json.dumps(result, ensure_ascii=False))
        os._exit(1)

    GLib.timeout_add(150, wait_for_window)
    GLib.timeout_add_seconds(WATCHDOG_SECONDS, watchdog)
    app.run([])
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result["stage"] == "measured" else 1


if __name__ == "__main__":
    sys.exit(main())
