#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""
Test de fumée de l'interface graphique réelle (GTK4), sans intervention :
ouvre la fenêtre, attend la fin de la détection, lance une vraie conversion
avec le moteur, puis imprime en JSON ce que l'utilisateur aurait vu
(titre, libellés, journal).

Il faut un écran : dans un environnement sans session graphique, lancer via

    xvfb-run -a -s "-screen 0 1280x900x24" python3 tests/gui_smoke.py <dossier-d-images>

Variables d'environnement utiles (réservées au développement et aux tests) :
    CONVERT_IMAGES_ENGINE     chemin du binaire convert-images-engine
    CONVERT_IMAGES_LOCALEDIR  dossier de catalogues compilés (.mo)
    LANGUAGE                  langue à tester (fr, es, de, en…)
    GUI_SMOKE_SHOTS           si défini : dossier où enregistrer des captures
                              d'écran (nécessite ImageMagick « import »)
"""

import importlib.machinery
import importlib.util
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import GLib, Gtk  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
GUI_PATH = ROOT / "nautilus-extension" / "convert-images-gui"
WATCHDOG_SECONDS = 60


def load_gui():
    loader = importlib.machinery.SourceFileLoader("convert_images_gui", str(GUI_PATH))
    spec = importlib.util.spec_from_loader("convert_images_gui", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def screenshot(name):
    target = os.environ.get("GUI_SMOKE_SHOTS")
    if not target or not shutil.which("import"):
        return
    Path(target).mkdir(parents=True, exist_ok=True)
    subprocess.run(["import", "-window", "root", str(Path(target) / f"{name}.png")], check=False)


def buffer_text(buf):
    return buf.get_text(buf.get_start_iter(), buf.get_end_iter(), False)


def main():
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2

    gui = load_gui()
    result = {"language": os.environ.get("LANGUAGE", ""), "stage": "start"}
    state = {"win": None, "phase": "detect", "ticks": 0}

    class SmokeApp(gui.ConvertImagesApp):
        def do_activate(self):
            super().do_activate()
            state["win"] = self.get_active_window()

    app = SmokeApp([sys.argv[1]])

    def tick():
        state["ticks"] += 1
        win = state["win"]
        if win is None:
            return True
        if state["phase"] == "detect" and win.options_box.get_visible():
            result["stage"] = "detected"
            result["title"] = win.get_title()
            result["status_after_detection"] = win.status_label.get_text()
            result["convert_button"] = win.convert_btn.get_label()
            result["quit_button"] = win.quit_btn.get_label()
            result["quality_label"] = win.quality_label.get_label()
            result["format_choices"] = [
                win.format_dropdown.get_model().get_string(i)
                for i in range(win.format_dropdown.get_model().get_n_items())
            ]
            result["collision_choices"] = [
                win.collision_dropdown.get_model().get_string(i)
                for i in range(win.collision_dropdown.get_model().get_n_items())
            ]
            state["phase"] = "shot-options"
            GLib.timeout_add(700, tick_shot_options)
            return False
        return True

    def tick_shot_options():
        win = state["win"]
        screenshot("1-options")
        win._on_convert_clicked(None)
        state["phase"] = "convert"
        GLib.timeout_add(200, tick_convert)
        return False

    def tick_convert():
        win = state["win"]
        if not win.conversion_in_progress and win.open_dest_btn.get_visible():
            result["stage"] = "converted"
            result["status_after_conversion"] = win.status_label.get_text()
            result["log"] = buffer_text(win.log_buffer)
            result["open_dest_button"] = win.open_dest_btn.get_label()
            GLib.timeout_add(700, tick_shot_end)
            return False
        return True

    def tick_shot_end():
        screenshot("2-converted")
        app.quit()
        return False

    def watchdog():
        result["stage"] = result["stage"] + " (TIMEOUT)"
        print(json.dumps(result, ensure_ascii=False))
        os._exit(1)

    GLib.timeout_add(150, tick)
    GLib.timeout_add_seconds(WATCHDOG_SECONDS, watchdog)
    app.run([])
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result["stage"] == "converted" else 1


if __name__ == "__main__":
    sys.exit(main())
