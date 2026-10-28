#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""
Lance l'interface INSTALLÉE (celle du paquet) sous Xvfb avec le moteur installé,
dans une langue donnée, et vérifie ce que l'utilisateur aurait vu.

    run_smoke.py <langue> <dossier-d-échantillons>

Variables d'environnement (pour tester hors paquet) :
    GUI_BIN     interface à lancer           (défaut : /usr/bin/convert-images-gui)
    GUI_SMOKE   test de fumée de l'interface (défaut : tests/gui_smoke.py du dépôt)
    CONVERT_IMAGES_ENGINE / CONVERT_IMAGES_LOCALEDIR : transmises telles quelles.

Code de sortie : 0 si tout est conforme, 1 sinon.
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

# (titre de la fenêtre, bouton Convertir, étiquette d'erreur, mot de fin)
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

    # gui_smoke.py cherche l'interface à <racine>/nautilus-extension/convert-images-gui :
    # on fabrique une racine temporaire dont ce chemin pointe vers l'interface installée.
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
            print(f"  [ÉCHEC] {language} : délai dépassé (120 s)")
            return 1

    lines = [ln for ln in r.stdout.splitlines() if ln.strip().startswith("{")]
    if not lines:
        print(f"  [ÉCHEC] {language} : aucun résultat de l'interface")
        print("      sortie standard :", r.stdout.strip()[-600:])
        print("      erreurs :", r.stderr.strip()[-1200:])
        return 1
    res = json.loads(lines[-1])

    problems = []
    if res.get("stage") != "converted":
        problems.append(f"étape atteinte : {res.get('stage')!r} au lieu de 'converted'")
    if res.get("title") != title:
        problems.append(f"titre {res.get('title')!r} au lieu de {title!r}")
    if res.get("convert_button") != convert:
        problems.append(f"bouton {res.get('convert_button')!r} au lieu de {convert!r}")
    log = res.get("log", "")
    if "[OK]" not in log:
        problems.append("aucune conversion réussie dans le journal")
    if error_tag not in log:
        problems.append(f"étiquette d'erreur {error_tag!r} absente (le faux RAW doit échouer)")
    if finished not in log:
        problems.append(f"mot de fin {finished!r} absent du journal")

    if problems:
        print(f"  [ÉCHEC] {language} : " + " ; ".join(problems))
        print("      journal vu par l'utilisateur :")
        print("      " + log.replace("\n", "\n      "))
        return 1
    print(f"  [OK]    {language} : « {title} », conversion réussie, erreur du faux RAW traduite, journal complet")
    return 0


if __name__ == "__main__":
    sys.exit(main())
