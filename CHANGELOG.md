<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Changelog

🇫🇷 [Version française](CHANGELOG.fr.md)

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

As for linuxdoctor, `VERSION` is not shipped with the source code: it
belongs to your local environment, advanced only by your own successful runs
of `build-deb.sh`/`build-rpm.sh`. The entries in this changelog therefore use
a date rather than a version number.

## [Unreleased]

## 2026-10-30 — v1.3.4

Maintenance release: no functional change (the engine, the Nautilus
extension, the GUI and the `.deb` / `.rpm` packages are identical to the
previous version). Documentation only.

### Changed

- **`vendor/README` in both languages**: `vendor/README.md` (English, shown
  by default on GitHub) and `vendor/README.fr.md` (French), with a link to
  switch language at the top of each file.
- `packaging/build-packages.sh` (the alternative packaging script) now also
  ships the French `README.fr.md` and `CHANGELOG.fr.md`, as `build-deb.sh` and
  `build-rpm.sh` already do.

## 2026-10-29 — v1.3.3

Maintenance release: no functional change (the engine, the Nautilus
extension and the GUI are identical to the previous version).

### Changed

- **Bilingual documentation**: `ARCHITECTURE`, `CONTRIBUTING`,
  `PROJECT_CONTEXT` and `CHANGELOG` now exist in English (`X.md`, shown by
  default on GitHub) and in French (`X.fr.md`), with a link to switch
  language at the top of each file. The `.deb` and `.rpm` packages now ship
  both versions in `/usr/share/doc/nautilus-convert-images/`.
- **Release notes are published in English first, then in French**, like the
  README (English by default). They come from today's entry in `CHANGELOG.md`
  (English) and in `CHANGELOG.fr.md` (French): `release.sh` stops before
  changing anything if either is missing.
- `release.sh`: when `VERSION` is already published (local tag, GitHub tag or
  existing release), the error message now says what to do —
  `./build-deb.sh --patch --yes` then `./build-rpm.sh --no-version-change --yes`
  (or `--minor` / `--major`) to move on to the next version.

## 2026-10-29 — v1.3.2

### Added

- **Test of the `.rpm` package in a real Fedora**
  (`tests/fedora/test-fedora.sh`): starts a Fedora container (podman or
  docker), installs the `.rpm` with `dnf`, checks its contents, the engine,
  GTK 4 and the Nautilus extension (real `nautilus-python` bindings), runs the
  full interface under Xvfb in the four languages, then uninstalls. If GTK 4
  is unusable, it identifies the missing package. To be run before publishing
  a release (see `CONTRIBUTING.md`).
- Test of the install script (`tests/test_postinst.py`): fake Nautilus,
  supported and unsupported languages, variable priority order, comparison
  with the language `gettext` really picks.

### Changed

- **Install message in the system language.** When installing the package
  restarts Nautilus, the message is displayed in English, French, Spanish or
  German depending on the session language (same rules as the menu entry:
  `LANGUAGE`, `LC_ALL`, `LC_MESSAGES`, `LANG`), falling back to English for
  any other language. It used to be French only. The Spanish and German
  translations have not been reviewed by native speakers.

## 2026-10-28 — v1.3.1

### Fixed

- **`.rpm` package: the interface did not start on a minimal Fedora.** From
  Python, GTK 4 needs the introspection file of `cairo`
  (`cairo-1.0.typelib`), provided by `gobject-introspection`; neither `gtk4`
  nor `python3-gobject` installs it. The menu appeared but a click launched
  nothing. `gobject-introspection` is now declared as a dependency, and
  `release.sh` refuses to publish a `.rpm` that does not declare it. Found by
  installing the v1.3.0 `.rpm` in a real Fedora 44 (container); with the
  dependency, the installation, the Nautilus extension and the interface in
  the four languages work. The `.deb` was not affected (it depends on
  `gir1.2-gtk-4.0`).
- **Interface log: long lines now wrap.** A path or a detailed error message
  (several hundred characters long) was cut off at the window edge and forced
  horizontal scrolling; it is now broken at spaces, or at the character for a
  path without spaces. New test `tests/test_gui_log.py`, which measures the
  layout in the real interface (under Xvfb).

### Changed

- **The README shown by default on GitHub is now in English**: `README.md` is
  the English version and the French version becomes `README.fr.md`
  (`README.en.md` disappears). Both are shipped in the `.deb` and `.rpm`
  packages.
- **More accurate Fedora / RHEL documentation**: the `.rpm` is tested on
  Fedora 44; the RHEL 10 family (with EPEL 10) is not tested; RHEL, Rocky and
  AlmaLinux 8 and 9 are not supported (their `nautilus-python`, 1.2.3, is too
  old for the Nautilus 4 API).

## 2026-10-28 — v1.3.0

### Added

- **Multilingual interface: English, French, Spanish and German.** The
  language is chosen automatically from the session (`LANGUAGE`, `LC_ALL`,
  `LC_MESSAGES`, `LANG`) and English is the fallback for any other language.
  Translated: the Nautilus context-menu entry, the window (labels, formats,
  collisions, log, dialogs), the engine's error messages and the `.desktop`
  file. Technical: gettext, domain `nautilus-convert-images`, `po/*.po`
  catalogs compiled to `.mo` at packaging time and installed in
  `/usr/share/locale`. No runtime dependency added.
- `po/update-po.sh` (regenerates the `.pot` template and updates the
  catalogs) and a "Translating the interface" section in `CONTRIBUTING.md` to
  fix a translation or add a language.
- Python tests (`tests/`): complete catalogs, `{…}` fields identical to the
  source, engine ↔ GUI message contract, Nautilus menu entry, and the real
  GUI launched under Xvfb in each language with the real engine.
- `README.en.md`: "Languages" section; the "interface in French only"
  remark is removed.

### Changed

- **The engine messages are now in English**: `message` fields of the JSON
  stream (failed `file_done`, `fatal_error`), help and errors of
  `convert-images-engine`. The GUI translates them; an unknown message is
  displayed as is, in English. Impact: a script that read these messages in
  French must be adapted (the JSON schema does not change).
- `build-deb.sh` and `build-rpm.sh` require `msgfmt` (`gettext` package) and
  stop, with `Cargo.toml` restored, if a catalog is invalid. `release.sh`
  checks that each package contains one translation per language in `po/`.

### Notes

- The Spanish and German translations were written with Claude's help and
  have not been reviewed by native speakers.
- The error text returned by `rawloader` or LibRaw stays in English
  (third-party libraries).

## 2026-10-27 — v1.2.0

### Added

- **LibRaw fallback** for the RAW files that `rawloader` cannot read,
  typically a camera missing from its database (the case met with the `.arw`
  files of the Sony DSC-RX100M6, rejected until then). Order:
  `rawloader`/`imagepipe` first, LibRaw next, and if both fail the error is
  displayed for that file and the batch continues.
- LibRaw 0.21.3 is bundled and statically compiled (`vendor/libraw-sys`): no
  library to install, no dependency added to the `.deb`/`.rpm` packages. Only
  `g++` is required at build time (the first build takes longer).
- Unit tests for decoding (`cargo test`) with a synthetic DNG generated on
  the fly.

### Fixed

- A rejected RAW displayed `imagepipe`'s generic message ("Don't know how to
  decode image"), which hid the real cause; `rawloader`'s exact error is now
  reported.
- An internal panic of a decoder on a corrupt file stopped the whole engine;
  it is now converted into an error for that file only.

### Changed

- Documentation: the "no `libraw`" choice is replaced by "bundled LibRaw as a
  fallback" (see `ARCHITECTURE.md`, "Dependency philosophy"), and the state of
  RAW support is clarified.

## 2026-10-27 — v1.1.1

Maintenance release: no functional change (the engine, the Nautilus
extension and the GUI are identical to the previous version).

### Added

- `release.sh`: publication of the GitHub release (preliminary checks,
  rebuilding the packages if needed, commit and push, creation of the release
  with both packages and their `.sha256` files).

### Changed

- `README.md`: usage-oriented presentation (why use it, use cases, supported
  formats), installation through `.deb`/`.rpm` packages and verification of
  the downloads; removal of obsolete passages (delivery by archive, `VERSION`
  "absent").
- Publication: each package is published with its own `.sha256` file (there
  is no global `SHA256SUMS` any more).

## 2026-10-26

First stable release published on GitHub (tag `v1.1.0`, `.deb` and `.rpm`
packages).

## 2026-09-15

First version.

### Added

- Conversion engine (`convert-images-engine`, Rust): format detection (JPEG,
  PNG, TIFF, BMP, GIF, WebP and RAW formats — CR2, CR3, NEF, ARW, DNG, ORF,
  RAF, RW2, PEF, SRW, X3F, etc. — see `ARCHITECTURE.md` for the full list and
  the detection strategy), lossless conversion to PNG/TIFF/BMP/WebP and to
  JPEG with adjustable quality (100 by default), always at full resolution
  and without cropping.
- Nautilus extension (`convert_images_nautilus.py`, nautilus-python):
  context-menu entry on a selection of files/folders and on a folder's
  background.
- Standalone GTK4 graphical interface (`convert-images-gui`): real-time
  detection, choice of destination format, JPEG quality, destination folder
  (with creation of a new folder), file-name collision policy, progress and
  conversion log.
- `.deb` and `.rpm` packaging through `fpm` (`build-deb.sh` /
  `build-rpm.sh`), on the same model as `linuxdoctor`: interactive or
  flag-driven versioning, `VERSION`/`Cargo.toml` updated only after a
  complete successful build, staging in a temporary folder with normalized
  permissions.
- Complete documentation: `README.md`, `PROJECT_CONTEXT.md` (vision and
  principles), `ARCHITECTURE.md` (canonical technical contract),
  `CONTRIBUTING.md`.
- "Quit" button in the GUI, always visible (including during detection,
  before the rest of the options appear). It also intercepts closing through
  the window's cross (`close-request`) to apply the same rule. If a
  conversion is running when quitting, a dialog (`Gtk.AlertDialog`) warns
  that the files already converted will stay on disk but the following ones
  will not be processed, with an explicit choice "Cancel" (default) / "Quit
  anyway"; with no conversion running, closing is immediate, with no dialog.

### Changed

- Destination format selected by default in the GUI: JPEG instead of PNG
  (explicit request; PNG is of course still available in the drop-down
  menu).

### Fixed

- Reported bug: the menu entry did not appear at all in Nautilus. Cause
  identified and confirmed by reproduction (`nautilus` launched from a
  terminal displayed the trace): `convert_images_nautilus.py` pinned
  `gi.require_version("Nautilus", "4.0")`, whereas on the user's machine (a
  more recent Nautilus than the one in the development sandbox) only the
  `Nautilus-4.1` typelib is installed — `4.0` simply does not exist on that
  system. The same pinning would have been a problem anyway even if `4.0` had
  existed: when the file runs, the host Nautilus process has already loaded
  its own typelib (`gi.require_version` can no longer change a version
  already loaded for the process), so any version pinned here other than the
  one actually running would have failed with "already loaded with version
  X". Fixed by removing the version pinning entirely for `Nautilus` (the
  `GObject` one poses no risk: only one introspection version exists for that
  namespace). Verified that the extension loads without error both when
  `Nautilus` is not loaded yet and when it is already loaded at a given
  version.

### Notable technical choices

- RAW decoding in pure Rust (`rawloader` + `imagepipe`), with no dependency
  on `libraw` — unlike `raw-thumbs` — to simplify packaging: no system C
  library to link against.
- Binaries installed under `/usr` (never `/usr/local`), a lesson taken
  directly from `raw-thumbs`: Nautilus's bwrap sandbox does not mount
  `/usr/local`, which would make the extension invisible.
- Some Rust crate versions are pinned in `Cargo.toml` (`clap`, `image`,
  `imagepipe`, `blake3`, `rayon`, `half`, `exr`, `uuid`, `lebe`,
  `rayon-core`) to stay compatible with a Rust 1.75 toolchain — see the
  "Toolchain note" section of `README.md`, the same situation as documented in
  `linuxdoctor`'s changelog for `clap` and `unicode-segmentation`.
