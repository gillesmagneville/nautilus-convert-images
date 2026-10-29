<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Contributing to nautilus-convert-images

🇫🇷 [Version française](CONTRIBUTING.fr.md)

Thank you for your interest in this project! This document explains how to
report a problem, suggest an improvement, or contribute code.

## Reporting a bug

Open an issue stating:

- your distribution and the Nautilus version (`nautilus --version`)
- the exact command used, if you went through the command-line engine
  (`convert-images-engine detect ...` /
  `convert-images-engine convert ...`)
- the source format and the destination format involved
- the observed behavior vs the expected one
- if possible, the engine's JSON output (`--output-dir` can be a temporary
  folder, to reproduce the problem safely without touching your real photos)

## Suggesting an improvement

Open an issue describing the need before writing any code, especially for a
new destination format — see `PROJECT_CONTEXT.md` for what falls within the
project's scope and what does not.

## Contributing code

1. Fork the repository and create a branch from `main`.
2. Check that everything passes before opening a pull request:

   ```bash
   cargo build
   cargo fmt --check
   python3 -m py_compile nautilus-extension/convert-images-gui \
                          nautilus-extension/convert_images_nautilus.py
   python3 -m unittest discover -s tests -v
   ```

   The Python tests need `gettext`; those that launch the real GUI also need
   PyGObject/GTK4, `xvfb`, ImageMagick and the compiled engine
   (`cargo build --release`); they are skipped if a tool is missing.

3. Describe in the pull request what changes and why.

## Adding a new destination format

This is the most common kind of contribution. The exact contract (the
lossless/depth/alpha table, the code points to change) is defined in
`ARCHITECTURE.md`, in the "Conversion" section ("Extension point — adding a
new destination format"). In short:

1. `src/convert.rs` — new `TargetFormat` variant + encoding case.
2. `src/main.rs` — entry in the output of the `formats` subcommand.
3. `nautilus-extension/convert-images-gui` — entry in `FORMAT_CHOICES`.
4. `ARCHITECTURE.md` — update the formats table.

### Rules for any new format

- Never advertise a format as "lossless" if it really is not — see
  "Reliability and transparency" in `PROJECT_CONTEXT.md`. If in doubt, check
  with a pixel-by-pixel comparison (see the "Tests" section of `README.md`
  for the method used so far).
- No cropping or resizing added, even as an option, without discussing it in
  an issue first — it is a founding principle of the project
  (`PROJECT_CONTEXT.md`, principle no. 2).

## Translating the interface

The interface exists in English (the fallback language), French, Spanish and
German. The Spanish and German translations have not been reviewed by native
speakers: a review is a valuable contribution, even for a single sentence. No
programming knowledge is needed — a `po/<language>.po` file is a text file
with, for each message, a `msgid` (the English) and a `msgstr` (the
translation).

**Fixing a translation**: edit the `msgstr` in `po/<language>.po`, then run
`python3 -m unittest discover -s tests -v`.

**Adding a language** (for example Italian, code `it`):

```bash
sudo apt install gettext      # msgmerge, msgfmt
msginit --no-translator --locale=it -i po/nautilus-convert-images.pot -o po/it.po
# translate po/it.po with a text editor or Poedit, then:
./po/update-po.sh
python3 -m unittest discover -s tests -v
```

To try the result without installing the package:

```bash
mkdir -p /tmp/locale/it/LC_MESSAGES
msgfmt -o /tmp/locale/it/LC_MESSAGES/nautilus-convert-images.mo po/it.po
CONVERT_IMAGES_LOCALEDIR=/tmp/locale LANGUAGE=it \
  CONVERT_IMAGES_ENGINE=./target/release/convert-images-engine \
  python3 nautilus-extension/convert-images-gui ~/Photos
```

Please observe the following:

- A catalog must be **complete** (no empty or "fuzzy" entry) to pass the
  tests: a half-translated catalog would display an interface mixing two
  languages.
- Keep the fields in braces (`{ok}`, `{folder}`…) **exactly** as they are:
  they can be moved within the sentence, but not renamed or translated.
  `msgfmt --check` (run by `po/update-po.sh` and by the package scripts)
  rejects a catalog that does not follow this rule.
- Read the `#.` ("TRANSLATORS") comments above some messages: they explain
  the context.
- A new language is picked up automatically by `build-deb.sh`,
  `build-rpm.sh` and `release.sh` as soon as `po/<language>.po` exists; also
  add the `Name[it]`, `GenericName[it]` and `Comment[it]` keys to
  `packaging/nautilus-convert-images.desktop`, and the language to the
  `GuiSmokeTests` test if you want it covered.
- If you add or change a text in the code: write it in English with
  `_("…")`, run `po/update-po.sh`, and translate the new entries (at least
  into French, the author's language). See "Internationalization" in
  `ARCHITECTURE.md`, in particular for the engine messages.

## Testing the `.rpm` package in a real Fedora

Before publishing a release, the `.rpm` is tested in a real Fedora, without
installing anything on your machine, thanks to a container (podman or
docker):

```bash
sudo apt install podman                 # once
tests/fedora/test-fedora.sh             # takes the .rpm present at the root of the repository
tests/fedora/test-fedora.sh nautilus-convert-images-X.Y.Z-1.x86_64.rpm 43   # another file, another Fedora version
```

The script installs the package with `dnf` (Fedora resolves the
dependencies), checks its contents, runs the engine, checks GTK 4 and the
Nautilus extension with the real `nautilus-python` bindings, runs the full
interface under Xvfb in the four languages, then uninstalls. It ends with
`RÉSULTAT : TOUT EST OK` (followed by the number of checks that passed).

If GTK 4 is unusable, the test works out on its own which Fedora package is
missing and reports it (`DÉPENDANCE MANQUANTE AU PAQUET`): this is how the
`gobject-introspection` dependency, added in v1.3.1, was found.

This test needs the network (Fedora image, `dnf` packages): it is not run by
`unittest discover`. It validates the installation and the interface, but not
a real click in a Nautilus session; it therefore does not replace a trial on
a Fedora desktop.

## Code style

- `cargo fmt` before opening a pull request.
- Stable Rust only, no nightly features.
- The engine (`src/`) must never depend on GTK or Nautilus — see "Overview"
  in `ARCHITECTURE.md`.
- Any new dependency must be justified (see "Dependency philosophy" in
  `ARCHITECTURE.md`).
- If a dependency has to be pinned to a precise version to stay compatible
  with an older Rust toolchain, document why in a comment in `Cargo.toml`,
  like the entries already there.

## Documentation

If your change alters observable behavior (new format, new CLI option, new
JSON schema, new interface text), update `CHANGELOG.md` and `CHANGELOG.fr.md`
in the same pull request, under `[Unreleased]` (`[Non publié]` in the French
file), and `ARCHITECTURE.md` / `ARCHITECTURE.fr.md` if the technical contract
changes.

Every document exists in two languages: English (`README.md`,
`PROJECT_CONTEXT.md`, `ARCHITECTURE.md`, `CONTRIBUTING.md`, `CHANGELOG.md`,
shown by default on GitHub) and French (the same names with `.fr.md`). If you
change one, change the other. If you only write one language, say so in the
pull request and the maintainer will translate it.

Release notes are published in English first, then in French. They are taken
from today's entry in `CHANGELOG.md` and `CHANGELOG.fr.md`; `release.sh`
refuses to publish if either file lacks it.

## Questions

For any question that does not fit the cases above, simply open an issue.

## License

By contributing, you agree that your contributions will be released under
the same license as the project (GPL-3.0-only).
