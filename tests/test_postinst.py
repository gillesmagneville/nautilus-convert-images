#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""
Tests du script post-installation (packaging/postinst) : le message affiché
quand Nautilus est redémarré doit suivre la langue du système (anglais,
français, espagnol, allemand ; repli sur l'anglais), avec les mêmes règles que
gettext, donc que l'entrée de menu elle-même. À lancer depuis la racine du
dépôt :

    python3 -m unittest discover -s tests -v

Le script est exécuté avec un faux « nautilus » et un faux « pgrep » placés en
tête du PATH : rien n'est redémarré pour de vrai.
"""

import gettext
import os
import shutil
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
POSTINST = ROOT / "packaging" / "postinst"
DOMAIN = "nautilus-convert-images"
LANGS = ("fr", "es", "de")

# Un fragment propre à chaque langue, pour reconnaître le message affiché.
MARKERS = {
    "en": "was restarted to enable the new menu entry",
    "fr": "a été redémarré pour activer la nouvelle entrée de menu",
    "es": "se ha reiniciado para activar la nueva entrada de menú",
    "de": "wurde neu gestartet, um den neuen Menüeintrag zu aktivieren",
}

# (variables d'environnement, langue attendue). Chaque cas est aussi comparé à
# la recherche gettext réelle de Python (GettextEquivalenceTests).
CASES = [
    ({}, "en"),
    ({"LANG": "en_US.UTF-8"}, "en"),
    ({"LANG": "C"}, "en"),
    ({"LANG": "C.UTF-8"}, "en"),
    ({"LANG": "POSIX"}, "en"),
    ({"LANG": "fr_FR.UTF-8"}, "fr"),
    ({"LANG": "fr_CA.UTF-8"}, "fr"),
    ({"LANG": "fr_BE@euro"}, "fr"),
    ({"LANG": "fr"}, "fr"),
    ({"LANG": "fr.UTF-8"}, "fr"),
    ({"LANG": "es_ES.UTF-8"}, "es"),
    ({"LANG": "es_MX.UTF-8"}, "es"),
    ({"LANG": "es"}, "es"),
    ({"LANG": "de_DE.UTF-8"}, "de"),
    ({"LANG": "de_AT.UTF-8"}, "de"),
    ({"LANG": "de_DE@euro"}, "de"),
    ({"LANG": "de_CH.ISO-8859-1"}, "de"),
    # Langues sans catalogue : repli sur l'anglais.
    ({"LANG": "it_IT.UTF-8"}, "en"),
    ({"LANG": "ja_JP.UTF-8"}, "en"),
    ({"LANG": "pt_BR.UTF-8"}, "en"),
    ({"LANG": "franglais"}, "en"),
    ({"LANG": "defaut"}, "en"),
    # Ordre de priorité des variables.
    ({"LC_ALL": "de_DE.UTF-8", "LANG": "fr_FR.UTF-8"}, "de"),
    ({"LC_ALL": "C", "LANG": "fr_FR.UTF-8"}, "en"),
    ({"LC_MESSAGES": "es_ES.UTF-8", "LANG": "fr_FR.UTF-8"}, "es"),
    ({"LC_ALL": "", "LC_MESSAGES": "", "LANG": "fr_FR.UTF-8"}, "fr"),
    ({"LANGUAGE": "de", "LC_ALL": "fr_FR.UTF-8"}, "de"),
    ({"LANGUAGE": "", "LANG": "es_ES.UTF-8"}, "es"),
    # LANGUAGE : liste de langues, la première disponible gagne.
    ({"LANGUAGE": "de:fr", "LANG": "fr_FR.UTF-8"}, "de"),
    ({"LANGUAGE": "it:de", "LANG": "fr_FR.UTF-8"}, "de"),
    ({"LANGUAGE": "it:ja:es_ES:fr", "LANG": "en_US.UTF-8"}, "es"),
    ({"LANGUAGE": "fr_FR:fr:en_US:en"}, "fr"),
    ({"LANGUAGE": "en_US:en", "LANG": "en_US.UTF-8"}, "en"),
    ({"LANGUAGE": "it", "LANG": "fr_FR.UTF-8"}, "en"),
    ({"LANGUAGE": "it:ja", "LANG": "de_DE.UTF-8"}, "en"),
    # « C » arrête la recherche dans la liste.
    ({"LANGUAGE": "C:fr", "LANG": "fr_FR.UTF-8"}, "en"),
    ({"LANGUAGE": "it:C:de"}, "en"),
]


def language_of(output):
    """Langue du message affiché, ou None s'il n'est pas reconnu (ou ambigu)."""
    found = [lang for lang, marker in MARKERS.items() if marker in output]
    return found[0] if len(found) == 1 else None


class PostinstRunner:
    """Exécute le postinst avec de faux « nautilus » et « pgrep »."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp(prefix="cie-postinst-"))
        cls.log = cls.tmp / "calls.log"
        (cls.tmp / "home").mkdir()
        # Le strict nécessaire du système, sans nautilus ni pgrep réels.
        cls.sysbin = cls.tmp / "sysbin"
        cls.sysbin.mkdir()
        for tool in ("sh", "dash", "bash", "echo", "cat", "env"):
            found = shutil.which(tool)
            if found:
                (cls.sysbin / tool).symlink_to(found)
        cls.bin_running = cls._make_bin("running", pgrep_status=0, nautilus_status=0)
        cls.bin_stopped = cls._make_bin("stopped", pgrep_status=1, nautilus_status=0)
        cls.bin_absent = cls._make_bin("absent", pgrep_status=0, nautilus_status=None)
        cls.bin_failing = cls._make_bin("failing", pgrep_status=0, nautilus_status=3)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    @classmethod
    def _make_bin(cls, name, pgrep_status, nautilus_status):
        """pgrep répond avec le code donné ; nautilus (si présent) note ses appels."""
        directory = cls.tmp / name
        directory.mkdir()
        (directory / "pgrep").write_text(f"#!/bin/sh\nexit {pgrep_status}\n")
        (directory / "pgrep").chmod(0o755)
        if nautilus_status is not None:
            (directory / "nautilus").write_text(
                f'#!/bin/sh\necho "nautilus $*" >> "{cls.log}"\nexit {nautilus_status}\n'
            )
            (directory / "nautilus").chmod(0o755)
        return directory

    def run_postinst(self, bin_dir, env=None, shell="/bin/sh", cwd=None):
        """Retourne (processus terminé, liste des appels reçus par le faux nautilus)."""
        merged = {"PATH": f"{bin_dir}:{self.sysbin}", "HOME": str(self.tmp / "home")}
        merged.update(env or {})
        if self.log.exists():
            self.log.unlink()
        proc = subprocess.run(
            [shell, str(POSTINST)],
            env=merged,
            cwd=cwd,
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        # bash (« sh » sous Fedora) se plaint lui-même quand la locale demandée
        # n'est pas installée sur la machine : ce n'est pas le fait du script.
        proc.stderr = "".join(
            line for line in proc.stderr.splitlines(keepends=True) if "setlocale" not in line
        )
        calls = self.log.read_text().splitlines() if self.log.exists() else []
        return proc, calls


class PostinstTests(PostinstRunner, unittest.TestCase):
    def test_message_follows_language(self):
        for env, expected in CASES:
            with self.subTest(env=env, expected=expected):
                proc, _ = self.run_postinst(self.bin_running, env)
                self.assertEqual(proc.returncode, 0, proc.stderr)
                self.assertEqual(proc.stderr, "")
                self.assertEqual(language_of(proc.stdout), expected, proc.stdout)
                self.assertTrue(proc.stdout.startswith("nautilus-convert-images"))
                self.assertEqual(len(proc.stdout.strip().splitlines()), 1)

    def test_nautilus_is_quit_when_running(self):
        proc, calls = self.run_postinst(self.bin_running, {"LANG": "fr_FR.UTF-8"})
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(calls, ["nautilus -q"])

    def test_silent_when_nautilus_not_running(self):
        for env in ({}, {"LANG": "fr_FR.UTF-8"}):
            proc, calls = self.run_postinst(self.bin_stopped, env)
            self.assertEqual(proc.returncode, 0)
            self.assertEqual(proc.stdout, "")
            self.assertEqual(proc.stderr, "")
            self.assertEqual(calls, [])

    def test_silent_when_nautilus_not_installed(self):
        proc, calls = self.run_postinst(self.bin_absent, {"LANG": "de_DE.UTF-8"})
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(proc.stdout, "")
        self.assertEqual(calls, [])

    def test_exit_zero_even_if_nautilus_quit_fails(self):
        proc, _ = self.run_postinst(self.bin_failing, {"LANG": "es_ES.UTF-8"})
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(language_of(proc.stdout), "es")

    def test_works_with_posix_shells(self):
        """Le script doit rester du sh POSIX (dpkg et rpm le lancent avec sh)."""
        shells = [s for s in ("/bin/sh", shutil.which("dash"), shutil.which("bash")) if s]
        for shell in dict.fromkeys(shells):
            for env, expected in (
                ({"LANG": "de_DE.UTF-8"}, "de"),
                ({"LANGUAGE": "it:es"}, "es"),
                ({}, "en"),
            ):
                with self.subTest(shell=shell, env=env):
                    proc, _ = self.run_postinst(self.bin_running, env, shell=shell)
                    self.assertEqual(proc.returncode, 0, proc.stderr)
                    self.assertEqual(language_of(proc.stdout), expected)

    def test_odd_language_values_do_not_break_it(self):
        """Étoiles, espaces, « : » en trop : jamais d'erreur, toujours un message."""
        for value in ("*:fr", "fr *", "  :de", "::", "fr::de", "*"):
            with self.subTest(language=value):
                proc, _ = self.run_postinst(self.bin_running, {"LANGUAGE": value})
                self.assertEqual(proc.returncode, 0, proc.stderr)
                self.assertEqual(proc.stderr, "")
                self.assertIsNotNone(language_of(proc.stdout), proc.stdout)

    def test_wildcard_in_language_does_not_expand_to_files(self):
        """« * » dans LANGUAGE ne doit pas être remplacé par les fichiers du dossier courant."""
        workdir = self.tmp / "workdir"
        workdir.mkdir()
        for name in ("de", "fr", "es"):
            (workdir / name).touch()
        proc, _ = self.run_postinst(self.bin_running, {"LANGUAGE": "*"}, cwd=workdir)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(language_of(proc.stdout), "en", proc.stdout)

    def test_shell_syntax_is_valid(self):
        for shell in ("/bin/sh", shutil.which("dash"), shutil.which("bash")):
            if shell:
                subprocess.run([shell, "-n", str(POSTINST)], check=True)


def _write_empty_mo(path):
    """Catalogue gettext vide mais valide : suffit à gettext.find()."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(struct.pack("<7I", 0x950412DE, 0, 0, 28, 28, 0, 28))


class GettextEquivalenceTests(PostinstRunner, unittest.TestCase):
    """Le postinst doit choisir la même langue que gettext pour le menu."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.localedir = cls.tmp / "locale"
        for lang in LANGS:
            _write_empty_mo(cls.localedir / lang / "LC_MESSAGES" / f"{DOMAIN}.mo")

    def gettext_language(self, env):
        """Langue que gettext (donc le menu) choisirait avec ces variables."""
        names = ("LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG")
        saved = {k: os.environ.get(k) for k in names}
        try:
            for key in names:
                os.environ.pop(key, None)
            os.environ.update(env)
            found = gettext.find(DOMAIN, str(self.localedir))
        finally:
            for key, value in saved.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value
        return Path(found).parts[-3] if found else "en"

    def test_same_choice_as_gettext(self):
        for env, _ in CASES:
            with self.subTest(env=env):
                proc, _calls = self.run_postinst(self.bin_running, env)
                self.assertEqual(
                    language_of(proc.stdout),
                    self.gettext_language(env),
                    f"postinst et gettext divergent pour {env}",
                )


if __name__ == "__main__":
    unittest.main()
