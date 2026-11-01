#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""
Launches the INSTALLED GUI (the one from the package) under Xvfb with the installed engine,
in a given language, and checks what the user would have seen.

    run_smoke.py <language> <samples-folder>

Environment variables (to test outside a package):
    GUI_BIN     GUI to launch                (default: /usr/bin/convert-images-gui)
    GUI_SMOKE   smoke test of the GUI        (default: the repository's tests/gui_smoke.py)
    CONVERT_IMAGES_ENGINE / CONVERT_IMAGES_LOCALEDIR: passed through unchanged.

Exit code: 0 if everything is compliant, 1 otherwise.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
GUI_BIN = os.environ.get("GUI_BIN", "/usr/bin/convert-images-gui")
GUI_SMOKE = Path(os.environ.get("GUI_SMOKE", HERE.parent.parent / "gui_smoke.py"))  # tests/gui_smoke.py

# (window title, Convert button, error label, end word)
EXPECTED = {
    "en": ("Convert images", "Convert", "[ERROR]", "Finished"),
    "fr": ("Convertir les images", "Convertir", "[ERREUR]", "Terminé"),
    "es": ("Convertir imágenes", "Convertir", "[ERROR]", "Finalizado"),
    "de": ("Bilder konvertieren", "Konvertieren", "[FEHLER]", "Fertig"),
}


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in EXPECTED:
        print(__doc__, file=sys.stderr)
        return 2
    language, samples = sys.argv[1], sys.argv[2]
    title, convert, error_tag, finished = EXPECTED[language]

    # gui_smoke.py looks for the GUI at <root>/nautilus-extension/convert-images-gui:
    # a temporary root is built whose path points to the installed GUI.
    with tempfile.TemporaryDirectory(prefix="cie-fedora-") as root:
        (Path(root) / "nautilus-extension").mkdir()
        (Path(root) / "tests").mkdir()
        os.symlink(GUI_BIN, Path(root) / "nautilus-extension" / "convert-images-gui")
        shutil.copy(GUI_SMOKE, Path(root) / "tests" / "gui_smoke.py")

        env = dict(os.environ, LANGUAGE=language, LC_ALL="C.UTF-8", LANG="C.UTF-8",
                   GSK_RENDERER="cairo", GDK_BACKEND="x11")
        cmd = ["xvfb-run", "-a", "-s", "-screen 0 900x800x24", sys.executable,
               str(Path(root) / "tests" / "gui_smoke.py"), samples]
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=120)
        except subprocess.TimeoutExpired:
            print(f"  [FAIL]  {language}: timeout (120 s)")
            return 1

    lines = [ln for ln in r.stdout.splitlines() if ln.strip().startswith("{")]
    if not lines:
        print(f"  [FAIL]  {language}: no result from the GUI")
        print("      standard output:", r.stdout.strip()[-600:])
        print("      errors:", r.stderr.strip()[-1200:])
        return 1
    res = json.loads(lines[-1])

    problems = []
    if res.get("stage") != "converted":
        problems.append(f"stage reached: {res.get('stage')!r} instead of 'converted'")
    if res.get("title") != title:
        problems.append(f"title {res.get('title')!r} instead of {title!r}")
    if res.get("convert_button") != convert:
        problems.append(f"button {res.get('convert_button')!r} instead of {convert!r}")
    log = res.get("log", "")
    if "[OK]" not in log:
        problems.append("no successful conversion in the log")
    if error_tag not in log:
        problems.append(f"error label {error_tag!r} missing (the fake RAW must fail)")
    if finished not in log:
        problems.append(f"end word {finished!r} missing from the log")

    if problems:
        print(f"  [FAIL]  {language}: " + " ; ".join(problems))
        print("      log seen by the user:")
        print("      " + log.replace("\n", "\n      "))
        return 1
    print(f"  [OK]    {language}: {title!r}, conversion succeeded, error of the fake RAW translated, complete log")
    return 0


if __name__ == "__main__":
    sys.exit(main())
