#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""
Test de la mise en page du journal de l'interface : une ligne très longue
(chemin sans espace, message d'erreur détaillé) doit passer à la ligne et non
obliger à faire défiler horizontalement. À lancer depuis la racine du dépôt :

    python3 -m unittest discover -s tests -v

Ignoré (« skipped ») sans xvfb-run, sans PyGObject/GTK4 ou sans le binaire
convert-images-engine.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # import possible hors « discover »
from test_i18n import _find_engine, _gtk_available  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent


@unittest.skipUnless(shutil.which("xvfb-run"), "xvfb-run (paquet xvfb) absent")
@unittest.skipUnless(shutil.which("convert") or shutil.which("magick"), "ImageMagick absent")
@unittest.skipUnless(_gtk_available(), "PyGObject + GTK4 indisponibles pour cet interpréteur")
@unittest.skipUnless(_find_engine(), "binaire convert-images-engine introuvable (cargo build --release)")
class LogWrapTests(unittest.TestCase):
    def test_long_line_wraps_instead_of_overflowing(self):
        with tempfile.TemporaryDirectory(prefix="cie-log-") as tmp:
            im = shutil.which("magick") or shutil.which("convert")
            subprocess.run([im, "-size", "64x48", "gradient:red-blue", os.path.join(tmp, "a.jpg")], check=True)
            env = dict(os.environ, LANGUAGE="en", LC_ALL="C.UTF-8", LANG="C.UTF-8",
                       CONVERT_IMAGES_ENGINE=_find_engine())
            r = subprocess.run(
                ["xvfb-run", "-a", "-s", "-screen 0 900x800x24", sys.executable,
                 str(ROOT / "tests" / "gui_log_wrap.py"), tmp],
                capture_output=True, text=True, env=env, timeout=120,
            )
        lines = [ln for ln in r.stdout.splitlines() if ln.strip().startswith("{")]
        self.assertTrue(lines, f"pas de résultat JSON\nstdout={r.stdout}\nstderr={r.stderr}")
        m = json.loads(lines[-1])
        self.assertEqual(m["stage"], "measured", m)
        self.assertFalse(m["wrap_none"], "le journal ne passe pas à la ligne")
        # Rien à faire défiler horizontalement : le contenu tient dans la largeur visible.
        self.assertLessEqual(m["hscroll_upper"], m["hscroll_page"] + 1, m)
        self.assertLessEqual(m["view_width"], m["scroller_width"], m)


if __name__ == "__main__":
    unittest.main()
