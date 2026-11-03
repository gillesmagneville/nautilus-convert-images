#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""
Test of the layout of the interface log: a very long line (path without
spaces, detailed error message) must wrap and not force horizontal
scrolling. To be run from the root of the repository:

    python3 -m unittest discover -s tests -v

Skipped without xvfb-run, without PyGObject/GTK4 or without the
convert-images-engine binary.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # import works outside "discover" too
from test_i18n import _find_engine, _gtk_available  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent


@unittest.skipUnless(shutil.which("xvfb-run"), "xvfb-run (xvfb package) missing")
@unittest.skipUnless(shutil.which("convert") or shutil.which("magick"), "ImageMagick missing")
@unittest.skipUnless(_gtk_available(), "PyGObject + GTK4 unavailable for this interpreter")
@unittest.skipUnless(_find_engine(), "convert-images-engine binary not found (cargo build --release)")
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
        self.assertTrue(lines, f"no JSON result\nstdout={r.stdout}\nstderr={r.stderr}")
        m = json.loads(lines[-1])
        self.assertEqual(m["stage"], "measured", m)
        self.assertFalse(m["wrap_none"], "the log does not wrap")
        # Nothing to scroll horizontally: the content fits in the visible width.
        self.assertLessEqual(m["hscroll_upper"], m["hscroll_page"] + 1, m)
        self.assertLessEqual(m["view_width"], m["scroller_width"], m)


if __name__ == "__main__":
    unittest.main()
