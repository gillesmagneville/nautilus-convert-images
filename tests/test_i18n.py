#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""
Tests de l'internationalisation (catalogues gettext, traduction des
messages du moteur). À lancer depuis la racine du dépôt :

    python3 -m unittest discover -s tests -v

Les tests qui ont besoin des outils GNU gettext (msgfmt, xgettext) ou de
PyGObject/GTK4 sont ignorés (« skipped ») quand ils sont absents.
"""

import gettext
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PO_DIR = ROOT / "po"
GUI = ROOT / "nautilus-extension" / "convert-images-gui"
DOMAIN = "nautilus-convert-images"
LANGS = sorted(p.stem for p in PO_DIR.glob("*.po"))
PLACEHOLDER = re.compile(r"\{(\w+)\}")


def _compile_all(outdir):
    for lang in LANGS:
        target = Path(outdir) / lang / "LC_MESSAGES"
        target.mkdir(parents=True)
        subprocess.run(
            ["msgfmt", "--check", "-o", str(target / f"{DOMAIN}.mo"), str(PO_DIR / f"{lang}.po")],
            check=True,
        )


@unittest.skipUnless(shutil.which("msgfmt"), "msgfmt (paquet gettext) absent")
class CatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="cie-i18n-")
        _compile_all(cls.tmp)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def test_required_languages_present(self):
        for lang in ("fr", "es", "de"):
            self.assertIn(lang, LANGS)

    def test_no_untranslated_or_fuzzy_entries(self):
        for lang in LANGS:
            out = subprocess.run(
                ["msgfmt", "--check", "--statistics", "-o", os.devnull, str(PO_DIR / f"{lang}.po")],
                capture_output=True, text=True, check=True,
            )
            report = out.stderr + out.stdout
            self.assertNotIn("untranslated", report, f"{lang}: {report}")
            self.assertNotIn("fuzzy", report, f"{lang}: {report}")

    def test_placeholders_identical_to_the_source_text(self):
        for lang in LANGS:
            with open(Path(self.tmp) / lang / "LC_MESSAGES" / f"{DOMAIN}.mo", "rb") as f:
                catalog = gettext.GNUTranslations(f)._catalog
            for key, msgstr in catalog.items():
                if key == "":
                    continue  # en-tête
                msgid = key[0] if isinstance(key, tuple) else key
                self.assertEqual(
                    sorted(PLACEHOLDER.findall(msgid)),
                    sorted(PLACEHOLDER.findall(msgstr)),
                    f"{lang}: champs différents pour {msgid!r}",
                )


@unittest.skipUnless(shutil.which("xgettext"), "xgettext (paquet gettext) absent")
class TemplateFreshnessTests(unittest.TestCase):
    def test_pot_is_up_to_date_with_the_code(self):
        with tempfile.TemporaryDirectory() as d:
            fresh = Path(d) / "fresh.pot"
            subprocess.run(
                ["xgettext", "--language=Python", "--from-code=UTF-8", "--keyword=_",
                 "--keyword=N_", "--keyword=ngettext:1,2", "-o", str(fresh),
                 "nautilus-extension/convert-images-gui",
                 "nautilus-extension/convert_images_nautilus.py"],
                cwd=ROOT, check=True,
            )

            def msgids(path):
                text = Path(path).read_text(encoding="utf-8")
                return sorted(set(re.findall(r'^msgid (".*")$', text, flags=re.M)) - {'""'}
                              | set(re.findall(r'^msgid_plural (".*")$', text, flags=re.M)))

            self.assertEqual(
                msgids(fresh), msgids(PO_DIR / f"{DOMAIN}.pot"),
                "po/nautilus-convert-images.pot est périmé : lancez ./po/update-po.sh",
            )


class EngineContractTests(unittest.TestCase):
    """Les modèles de messages de l'IHM doivent exister dans le code Rust."""

    def test_every_template_is_emitted_by_the_engine(self):
        source = GUI.read_text(encoding="utf-8")
        m = re.search(r"ENGINE_MESSAGE_TEMPLATES = \[(.*?)\n\]", source, flags=re.S)
        self.assertIsNotNone(m, "liste ENGINE_MESSAGE_TEMPLATES introuvable")
        templates = eval("[" + m.group(1) + "]", {"N_": lambda s: s})
        rust = "\n".join(p.read_text(encoding="utf-8") for p in (ROOT / "src").glob("*.rs"))
        self.assertGreaterEqual(len(templates), 10)
        for template in templates:
            chunks = [c for c in PLACEHOLDER.split(template)[::2] if c.strip()]
            longest = max(chunks, key=len)
            self.assertIn(longest, rust, f"modèle sans équivalent dans src/*.rs : {template!r}")


_PROBE = r"""
import importlib.machinery, importlib.util, json, sys
loader = importlib.machinery.SourceFileLoader("gui", sys.argv[1])
spec = importlib.util.spec_from_loader("gui", loader)
gui = importlib.util.module_from_spec(spec)
loader.exec_module(gui)
tem = gui.translate_engine_message
out = {
  "skip": tem("skipped (the destination file already exists)"),
  "combined": tem('cannot open RAW file: RawLoaderError: "x {y}" ; LibRaw fallback: LibRaw: Input/output error'),
  "enc": tem("PNG encoding failed: disk full"),
  "internal": tem("rawloader: internal decoder error (corrupted file?)"),
  "unknown": tem("something the engine never says"),
  "none": tem(None),
  "label_unknown": gui.translate_format_label("Unknown"),
  "label_raw": gui.translate_format_label("RAW Sony (ARW)"),
  "plural0": gui.ngettext("{n} file detected: {details}", "{n} files detected: {details}", 0),
  "plural1": gui.ngettext("{n} file detected: {details}", "{n} files detected: {details}", 1),
  "plural2": gui.ngettext("{n} file detected: {details}", "{n} files detected: {details}", 2),
  "formats": [gui._(label) for _id, label in gui.FORMAT_CHOICES],
}
print(json.dumps(out, ensure_ascii=False))
"""


def _gtk_available():
    r = subprocess.run(
        [sys.executable, "-c", "import gi; gi.require_version('Gtk','4.0'); from gi.repository import Gtk"],
        capture_output=True,
    )
    return r.returncode == 0


@unittest.skipUnless(shutil.which("msgfmt"), "msgfmt (paquet gettext) absent")
@unittest.skipUnless(_gtk_available(), "PyGObject + GTK4 indisponibles pour cet interpréteur")
class RuntimeTranslationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="cie-i18n-")
        _compile_all(cls.tmp)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def probe(self, language):
        env = dict(os.environ, CONVERT_IMAGES_LOCALEDIR=self.tmp, LANGUAGE=language,
                   LC_ALL="C.UTF-8", LANG="C.UTF-8")
        r = subprocess.run([sys.executable, "-c", _PROBE, str(GUI)],
                           capture_output=True, text=True, env=env)
        self.assertEqual(r.returncode, 0, r.stderr)
        return json.loads(r.stdout)

    def test_french(self):
        r = self.probe("fr")
        self.assertEqual(r["skip"], "ignoré (le fichier de destination existe déjà)")
        self.assertEqual(
            r["combined"],
            'ouverture du fichier RAW impossible : RawLoaderError: "x {y}" ; '
            "repli LibRaw : LibRaw: Input/output error",
        )
        self.assertEqual(r["enc"], "échec de l'encodage PNG : disk full")
        self.assertEqual(r["internal"], "rawloader : erreur interne du décodeur (fichier corrompu ?)")
        self.assertEqual(r["label_unknown"], "Inconnu")
        self.assertEqual(r["label_raw"], "RAW Sony (ARW)")
        # français : 0 et 1 au singulier
        self.assertIn("fichier détecté", r["plural0"])
        self.assertIn("fichier détecté", r["plural1"])
        self.assertIn("fichiers détectés", r["plural2"])
        self.assertEqual(r["formats"][0], "JPEG (avec perte, qualité réglable)")

    def test_german_and_spanish(self):
        de, es = self.probe("de"), self.probe("es")
        self.assertEqual(de["enc"], "PNG-Kodierung fehlgeschlagen: disk full")
        self.assertEqual(de["plural1"], "{n} Datei erkannt: {details}")
        self.assertEqual(de["plural0"], "{n} Dateien erkannt: {details}")  # allemand : 0 au pluriel
        self.assertEqual(es["enc"], "error al codificar en PNG: disk full")
        self.assertEqual(es["plural2"], "{n} archivos detectados: {details}")

    def test_english_is_the_fallback_for_unsupported_languages(self):
        for language in ("it", "ja", "C", ""):
            r = self.probe(language)
            self.assertEqual(r["skip"], "skipped (the destination file already exists)", language)
            self.assertEqual(r["label_unknown"], "Unknown", language)
            self.assertEqual(r["formats"][1], "PNG (lossless)", language)

    def test_regional_variant_uses_the_base_language(self):
        r = self.probe("fr_CA.UTF-8")
        self.assertEqual(r["label_unknown"], "Inconnu")

    def test_unknown_or_non_string_messages_are_left_alone(self):
        r = self.probe("de")
        self.assertEqual(r["unknown"], "something the engine never says")
        self.assertIsNone(r["none"])


def _find_engine():
    candidates = [
        os.environ.get("CONVERT_IMAGES_ENGINE"),
        str(ROOT / "target" / "release" / "convert-images-engine"),
        "/usr/bin/convert-images-engine",
    ]
    for c in candidates:
        if c and os.access(c, os.X_OK):
            return c
    return None


@unittest.skipUnless(shutil.which("msgfmt"), "msgfmt (paquet gettext) absent")
@unittest.skipUnless(shutil.which("xvfb-run"), "xvfb-run (paquet xvfb) absent")
@unittest.skipUnless(shutil.which("convert") or shutil.which("magick"), "ImageMagick absent")
@unittest.skipUnless(_gtk_available(), "PyGObject + GTK4 indisponibles pour cet interpréteur")
@unittest.skipUnless(_find_engine(), "binaire convert-images-engine introuvable (cargo build --release)")
class GuiSmokeTests(unittest.TestCase):
    """Lance la vraie interface (sous Xvfb) avec le vrai moteur, dans chaque langue."""

    EXPECTED = {
        "en": ("Convert images", "Convert", "Quit", "[ERROR]", "Finished"),
        "fr": ("Convertir les images", "Convertir", "Quitter", "[ERREUR]", "Terminé"),
        "es": ("Convertir imágenes", "Convertir", "Salir", "[ERROR]", "Finalizado"),
        "de": ("Bilder konvertieren", "Konvertieren", "Beenden", "[FEHLER]", "Fertig"),
        "it": ("Convert images", "Convert", "Quit", "[ERROR]", "Finished"),  # repli anglais
    }

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="cie-gui-")
        _compile_all(os.path.join(cls.tmp, "locale"))
        cls.engine = _find_engine()

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def _make_samples(self, folder):
        os.makedirs(folder)
        im = shutil.which("magick") or shutil.which("convert")
        for name, grad in (("a.jpg", "red-blue"), ("b.png", "green-yellow")):
            subprocess.run([im, "-size", "64x48", f"gradient:{grad}", os.path.join(folder, name)], check=True)
        with open(os.path.join(folder, "bad.arw"), "wb") as f:
            f.write(os.urandom(2048))  # faux RAW : doit produire une erreur traduite

    def run_gui(self, language):
        samples = os.path.join(self.tmp, f"samples-{language}")
        self._make_samples(samples)
        env = dict(os.environ, LANGUAGE=language, LC_ALL="C.UTF-8", LANG="C.UTF-8",
                   CONVERT_IMAGES_ENGINE=self.engine,
                   CONVERT_IMAGES_LOCALEDIR=os.path.join(self.tmp, "locale"))
        r = subprocess.run(
            ["xvfb-run", "-a", "-s", "-screen 0 900x800x24", sys.executable,
             str(ROOT / "tests" / "gui_smoke.py"), samples],
            capture_output=True, text=True, env=env, timeout=120,
        )
        lines = [ln for ln in r.stdout.splitlines() if ln.strip().startswith("{")]
        self.assertTrue(lines, f"pas de résultat JSON\nstdout={r.stdout}\nstderr={r.stderr}")
        result = json.loads(lines[-1])
        self.assertEqual(result["stage"], "converted", result)
        return result

    def test_each_language(self):
        for language, (title, convert, quit_, error_tag, finished) in self.EXPECTED.items():
            with self.subTest(language=language):
                r = self.run_gui(language)
                self.assertEqual(r["title"], title)
                self.assertEqual(r["convert_button"], convert)
                self.assertEqual(r["quit_button"], quit_)
                self.assertIn(error_tag, r["log"])
                self.assertIn(finished, r["log"])
                self.assertIn("a (1).jpg", r["log"])  # collision « renommer » par défaut
                self.assertEqual(len(r["format_choices"]), 5)
                self.assertEqual(len(r["collision_choices"]), 3)


_EXT_PROBE = r"""
import importlib.util, json, sys, types
import gi
gi.require_version("GObject", "2.0")
from gi.repository import GObject

# Faux module Nautilus : le vrai n'existe que dans le processus Nautilus.
class _MenuItem:
    def __init__(self, name, label, tip):
        self.name, self.label, self.tip = name, label, tip
    def connect(self, *a, **k):
        pass
class _MenuProvider: pass
fake = types.ModuleType("gi.repository.Nautilus")
fake.MenuItem = _MenuItem
fake.MenuProvider = _MenuProvider
import gi.repository
gi.repository.Nautilus = fake
sys.modules["gi.repository.Nautilus"] = fake

spec = importlib.util.spec_from_file_location("ext", sys.argv[1])
ext = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ext)
item = ext.ConvertImagesMenuProvider()._make_item(["/tmp/x"])
print(json.dumps({"label": item.label, "tip": item.tip}, ensure_ascii=False))
"""


@unittest.skipUnless(shutil.which("msgfmt"), "msgfmt (paquet gettext) absent")
@unittest.skipUnless(_gtk_available(), "PyGObject + GTK4 indisponibles pour cet interpréteur")
class NautilusExtensionTests(unittest.TestCase):
    """L'entrée du menu contextuel de Nautilus doit suivre la langue."""

    EXT = ROOT / "nautilus-extension" / "convert_images_nautilus.py"
    EXPECTED = {
        "en": "Convert images…",
        "fr": "Convertir les images…",
        "es": "Convertir imágenes…",
        "de": "Bilder konvertieren …",
        "it": "Convert images…",  # repli anglais
    }

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="cie-ext-")
        _compile_all(cls.tmp)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def test_menu_entry_per_language(self):
        for language, label in self.EXPECTED.items():
            with self.subTest(language=language):
                env = dict(os.environ, CONVERT_IMAGES_LOCALEDIR=self.tmp, LANGUAGE=language,
                           LC_ALL="C.UTF-8", LANG="C.UTF-8")
                r = subprocess.run([sys.executable, "-c", _EXT_PROBE, str(self.EXT)],
                                   capture_output=True, text=True, env=env)
                self.assertEqual(r.returncode, 0, r.stderr)
                item = json.loads(r.stdout.strip().splitlines()[-1])
                self.assertEqual(item["label"], label)
                self.assertTrue(item["tip"])


class DesktopFileTests(unittest.TestCase):
    def test_desktop_entry_has_all_languages(self):
        text = (ROOT / "packaging" / "nautilus-convert-images.desktop").read_text(encoding="utf-8")
        for key in ("Name", "GenericName", "Comment"):
            self.assertRegex(text, rf"(?m)^{key}=.+$", f"{key} par défaut (anglais) manquant")
            for lang in ("fr", "es", "de"):
                self.assertRegex(text, rf"(?m)^{key}\[{lang}\]=.+$", f"{key}[{lang}] manquant")


if __name__ == "__main__":
    unittest.main()
