<!-- SPDX-License-Identifier: GPL-3.0-only -->

# nautilus-convert-images

🇫🇷 [Version française](README.fr.md)

**Convert your photos with a right-click, straight from Nautilus — RAW
included, at full resolution, with no cropping or resizing.**

[![Latest release](https://img.shields.io/github/v/release/gillesmagneville/nautilus-convert-images)](https://github.com/gillesmagneville/nautilus-convert-images/releases/latest)
[![License GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)

Select files or whole folders in GNOME Files, right-click →
**Convert images…**, choose the format and the destination folder:
that's all.

> **Note:** the user interface is available in **English, French, Spanish
> and German** (see [Languages](#languages)). The other documents
> (`PROJECT_CONTEXT.md` for the vision and principles, `ARCHITECTURE.md`
> for the technical contract, `CONTRIBUTING.md`, `CHANGELOG.md`) exist in
> **English and French**: each one has a link to switch language at the top,
> and the French files end in `.fr.md`.

## Why use it?

* **No detour** — no application to launch, no command line, no import:
  the conversion is in the context menu of your files.
* **Everything you have at hand** — RAW from many cameras (see "RAW
  compatibility"), JPEG, PNG, TIFF, BMP, GIF, WebP, even mixed in a single
  folder: the format of each file is detected, even when the extension is
  missing or misleading.
* **Your quality, intact** — full resolution, never any cropping or
  resizing; PNG, TIFF, BMP and WebP are truly lossless (transparency and
  16-bit depth preserved). For a RAW, this applies to the developed image,
  not to the original file: keep it.
* **Fast** — Rust engine, all CPU cores work in parallel on batches.
* **In control** — you see what was detected before starting, choose the
  destination folder (creating one is possible) and what happens if a name
  already exists (skip, rename, overwrite), then follow the progress live.
* **Light and free** — RAW decoders built into the program (nothing more
  to install), GPL-3.0 license.

| You have | You want | What to do |
|---|---|---|
| A folder of RAW files after a shoot | JPEGs to share | select it, choose JPEG (the default) |
| RAW files to pass to another program | A lossless image | choose TIFF or PNG (16-bit), and keep the RAW |
| A folder mixing CR2, TIFF and PNG | A single format everywhere | select everything, choose the format |
| Large BMP or PNG files | Smaller files, still lossless | choose lossless WebP |

## Installation

Download the package for your distribution from the
[releases](https://github.com/gillesmagneville/nautilus-convert-images/releases/latest)
page (`X.Y.Z` = version number), then:

```bash
# Debian, Ubuntu and derivatives
sudo apt install ./nautilus-convert-images_X.Y.Z_amd64.deb

# Fedora (tested on Fedora 44)
sudo dnf install ./nautilus-convert-images-X.Y.Z-1.x86_64.rpm
```

The `.rpm` needs `nautilus-python` 4.x (Nautilus 43 or later). `dnf` installs
it and the other dependencies by itself on Fedora. On the RHEL 10 family it
comes from EPEL 10 (not tested); RHEL, Rocky Linux and AlmaLinux 8 and 9 are
not supported, because their `nautilus-python` is too old.

Nautilus is restarted automatically to enable the menu entry. Each package
is published with its own `.sha256` file (there is no global `SHA256SUMS`).
To verify a download, put the package and its `.sha256` file in the same
folder:

```bash
sha256sum -c nautilus-convert-images_X.Y.Z_amd64.deb.sha256
```

## Usage

Right-click on a selection (files and/or folders) or on the background of a
folder → **Convert images…**. The GUI can also be launched manually,
outside Nautilus:

```bash
convert-images-gui ~/Photos/img001.cr2 ~/Photos/img002.jpg
```

## Languages

The interface — the context-menu entry, the window, labels and error
messages — is available in **English, French, Spanish and German**. The
language is chosen automatically from your session's language (the
`LANGUAGE`, `LC_ALL`, `LC_MESSAGES` or `LANG` variables); for any other
language, the interface is shown in English. To try a language without
changing your session:

```bash
LANGUAGE=de convert-images-gui ~/Photos/img001.jpg
```

After changing the session language, restart Nautilus (`nautilus -q`) so
that the menu entry follows.

* The Spanish and German translations have not yet been reviewed by native
  speakers: corrections are welcome (see `CONTRIBUTING.md`, which also
  explains how to add a language).
* Error messages produced by the engine itself are translated; text coming
  back from third-party libraries (for example the detail of a `rawloader`
  or LibRaw error) stays in English.
* The command-line engine (`convert-images-engine`, its help and its
  messages) is in English.
* The message printed when the package is installed (Nautilus restarted)
  follows the same language rules, with the same English fallback.

## Formats

| | Formats |
|---|---|
| **Sources** | RAW (recognized extensions: CR2/CR3, NEF/NRW, ARW/SRF/SR2, DNG, ORF, RAF, RW2, PEF, SRW, X3F, 3FR, RWL, GPR…; see "RAW compatibility"), JPEG, PNG, TIFF, BMP, GIF, WebP |
| **Destinations** | JPEG (adjustable quality, 100 by default), PNG, TIFF (uncompressed), BMP, lossless WebP (VP8L) |

PNG, TIFF, BMP and WebP are **genuinely lossless**, verified by pixel-by-pixel
comparison (alpha channel and 16-bit included). JPEG remains a lossy format
by nature — a limit of the format itself, not of this tool, and never
presented as anything else. Detection is done by extension, then by content
analysis, with an actual decoding attempt as a last resort. RAW files are
decoded at full resolution (active sensor area).

The engine, the extension and the GUI are decoupled (see
`ARCHITECTURE.md`): the engine (`convert-images-engine`) is a standalone CLI
executable, usable independently of Nautilus or GTK.

## RAW compatibility

Recognizing a file as RAW (by its extension) does not guarantee that it can
be decoded: it depends on the camera.

* **A conversion, not a development** — for a RAW input file, the result
  is the camera's raw data as it is: the camera's white balance and a
  conversion to sRGB, with no retouching (no lens correction — vignetting,
  distortion —, no sharpening or noise reduction, no creative exposure or
  contrast adjustment). It is therefore neither the rendering of the
  camera's JPEG (more contrasty, corners corrected, sometimes cropped to
  16:9 whereas the converted image covers the whole sensor), nor that of a
  RAW developer such as darktable or RawTherapee, which add their own
  default adjustments. For a finished result, convert to 16-bit TIFF or
  PNG and retouch in such a program.
* **Decoding order** — `rawloader` first; if it does not know the camera,
  automatic fallback to [LibRaw](https://www.libraw.org/), built into the
  program. If both fail, the error is shown for that file and the batch
  carries on with the next one.
* **Tested with real files** — only Sony ARW files, including those from
  the RX100 VI (absent from `rawloader`'s database, hence decoded by the
  fallback). Canon, Nikon, Fujifilm, Olympus, Panasonic, Pentax, Sigma,
  DNG… are supported according to what `rawloader` and LibRaw announce, but
  have not been verified by the author; color fidelity may vary from one
  camera to another.
* **Limits of the LibRaw fallback** — it is built without the optional
  libraries: it reads neither lossy-compressed (JPEG) DNG files nor
  floating-point compressed (deflate) DNG files, nor Sigma Foveon files
  (X3F; `rawloader` reads some of them). Canon's CR3 does not exist in
  `rawloader`: it therefore depends entirely on the fallback, and has not
  been tested.
* **Two decoders, two renderings** — the main decoder (`imagepipe`) applies
  a light base tone curve to go from the sensor's linear signal to a
  natural look; the LibRaw fallback does not, and its images tend to look
  darker. A batch that mixes cameras handled by one and by the other can
  therefore show slightly different brightness.
* **A file refused, or with doubtful colors?** Report it through the
  [issues](https://github.com/gillesmagneville/nautilus-convert-images/issues),
  stating the camera model.

## Getting set up

To build from source:

```bash
git clone https://github.com/gillesmagneville/nautilus-convert-images.git ~/Projects/nautilus-convert-images
cd ~/Projects/nautilus-convert-images
cargo build
```

Build dependencies for the GUI and the extension (not only the Rust
engine):

```bash
sudo apt-get install rustc cargo libgtk-4-dev python3-gi gir1.2-gtk-4.0 \
    python3-nautilus pkg-config build-essential gettext
```

`gettext` provides `msgfmt`, which compiles the translations (`po/*.po`)
when packaging; it is not needed for a plain `cargo build`.

`build-essential` provides `g++`, needed to compile the LibRaw (C++) built
into `vendor/`: the first build is therefore longer (a few minutes), later
ones are incremental.

## Packaging

Two scripts build native packages via [fpm](https://fpm.readthedocs.io/) —
`build-deb.sh` (Debian/Ubuntu) and `build-rpm.sh`
(Fedora/RHEL/Rocky/AlmaLinux). Both follow the same flow: choice of a
version increment (interactive or by flag), release-mode build, staging of
the engine + the GUI + the extension + the compiled translations + the
documentation, then packaging.
`VERSION` and `Cargo.toml` are only updated after a fully successful build
— a failed compilation or `fpm` run leaves the repository unchanged. A
short confirmation is asked before building, unless a version flag was
already given without an interactive terminal attached to stdin
(script/CI context — the flag itself counts as confirmation) or `--yes`/`-y`
is passed explicitly. Running without a version flag and without an
interactive terminal fails immediately with a clear message. The generated
`.rpm` file name contains a `-1` suffix after the version number (e.g.
`nautilus-convert-images-1.2.3-1.x86_64.rpm`) — this is the RPM "Release"
field, set to 1 by default by `fpm`. The `.deb` format has no such notion.
Neither `VERSION` nor `Cargo.toml` ever contain this suffix.

```bash
./build-deb.sh --patch   # or --minor / --major / --no-version-change
./build-rpm.sh --patch
./build-deb.sh --patch --yes   # without confirmation
./build-deb.sh --clean         # removes build artifacts and generated .deb files
```

`MAINTAINER` and `URL`, at the top of each script, are already filled in for
this repository; adapt them in a fork. Both scripts check that the required
tools are present (`fpm`, `cargo`, `msgfmt`, and `dpkg-deb` or `rpmbuild`
respectively) and explain what to install if something is missing — read
that message carefully: on a silent "no version increment took place", the
most likely cause is a failed tool check (for example `fpm` not actually
installed — it is installed with `gem install --user-install fpm`, not a
distribution package), since an increment is never written before a build
has fully succeeded.

`VERSION` is versioned with the code: it matches the tag of the latest
release.

### Publishing a release

After the usual builds (`VERSION` up to date, `.deb` and `.rpm` generated),
`release.sh` publishes the matching GitHub release: preliminary checks,
rebuilding the packages if needed, commit and push of `main`, then creation
of the release with both packages and one `.sha256` file per package. It
requires an authenticated [`gh`](https://cli.github.com/). If `VERSION` is
already published, it stops and tells you which build commands to run first
to move on to the next version. The release notes are published in English
first (like this README), then in French; they come from today's entry in
`CHANGELOG.md` (English) and in `CHANGELOG.fr.md` (French), both required.

```bash
./release.sh --dry-run   # preview, nothing is modified or published
./release.sh
```

## Runtime dependencies

The engine (`convert-images-engine`) depends on no external library beyond
what `cargo build` links statically — in particular there is no LibRaw
library to install: it is statically embedded (see "Dependency philosophy"
in `ARCHITECTURE.md`). The GUI and the extension need, at run time:
`python3-gi`, `gir1.2-gtk-4.0`, `python3-nautilus` (Debian/Ubuntu package
names; `python3-gobject`, `gtk4`, `gobject-introspection`, `nautilus-python`
on Fedora) — already
declared as dependencies by both packaging scripts. The translations add no
dependency: they rely on the `gettext` module of Python's standard library.

## Quickstart

The engine can also be used on its own, from the command line:

```bash
cargo build --release
./target/release/convert-images-engine formats
./target/release/convert-images-engine detect --recursive ~/Photos
./target/release/convert-images-engine convert --recursive ~/Photos \
    --output-dir ~/Photos/converted --format png
```

## Tests

The engine was validated by pixel-by-pixel comparison (PNG/TIFF/BMP/WebP
bit-identical to the source, including with an alpha channel and 16-bit
depth; JPEG with a minimal, expected difference at quality 100), the
Nautilus extension with the real GObject Introspection libraries, and the
GUI by an end-to-end scenario under Xvfb (detection → conversion → files
produced). The LibRaw fallback is covered by unit tests (`cargo test`) on a
synthetic DNG, and was verified on real `.arw` files from the Sony
DSC-RX100M6 (absent from `rawloader`'s database); fidelity on other cameras
is validated case by case.

```bash
cargo build --release && ./target/release/convert-images-engine formats
```

The translations and the GUI have their own Python tests (`tests/`):
complete catalogs, `{…}` placeholders identical to the source text, engine
messages translated, the Nautilus menu entry in each language, and the real
GUI launched under Xvfb with the real engine in English, French, Spanish
and German, falling back to English for an unsupported language. Another
test runs the install script (`packaging/postinst`) with a fake Nautilus and
checks that it picks the same language as `gettext` does. Tests that
need a missing tool (`msgfmt`, `xgettext`, PyGObject/GTK4, `xvfb-run`,
ImageMagick, a built engine) are skipped, not failed.

```bash
cargo build --release
python3 -m unittest discover -s tests -v
```

## Toolchain note

This project was developed and tested with `rustc`/`cargo` 1.75 (the apt
package of Ubuntu 24.04) — the same constraint as documented in the
`linuxdoctor` README for `clap`. Several dependencies are pinned in
`Cargo.toml` for this MSRV:

* `clap` at `4.5.57` — newer `clap_builder` versions (via `clap_lex` 1.x)
  declare `edition2024`, which requires Cargo ≥ 1.85 just to be parsed.
* `imagepipe` at `=0.5.0` (not just `0.5`) — `0.5.1` depends on `image`
  `^0.25`, which pulls in `moxcms`, also `edition2024`.
* `image` at `0.24` — the `0.25` branch has the same problem.
* `blake3` at `=1.8.2`, `rayon`/`rayon-core` at `1.10.0`/`1.12.1`, `half`
  at `2.4.1`, `exr` at `1.74.0`, `uuid` at `1.20.0`, `lebe` at `0.5.2` —
  transitive dependencies of `imagepipe`/`image`, each pinned to the latest
  version still compatible with Rust 1.75 (declared MSRV or `edition2024`
  required, depending on the case).

If you are on a newer toolchain (1.85+), all these constraints are safe to
relax — `cargo update` will pick up the current versions with no code
change. These pinned versions build and work perfectly in the meantime:
this is not a limit of the project, only of the test toolchain.

## Layout

```
nautilus-convert-images/
├── .gitignore
├── VERSION                  # current version (= tag of the latest release)
├── CHANGELOG.md              # Keep a Changelog format (+ CHANGELOG.fr.md)
├── CONTRIBUTING.md            # reporting a bug, adding a format, code style (+ CONTRIBUTING.fr.md)
├── build-deb.sh                 # .deb packaging (fpm)
├── build-rpm.sh                   # .rpm packaging (fpm)
├── release.sh                       # GitHub release publishing
├── Cargo.toml
├── Cargo.lock
├── README.md                  # English version (shown by default on GitHub; this file)
├── README.fr.md                 # French version
├── PROJECT_CONTEXT.md           # (+ PROJECT_CONTEXT.fr.md)
├── ARCHITECTURE.md              # (+ ARCHITECTURE.fr.md)
│
├── src/                       # convert-images-engine (Rust)
│   ├── main.rs                 # CLI entry point, streamed JSON output
│   ├── cli.rs                   # clap, recursive file enumeration
│   ├── formats.rs                # format detection (standard + RAW)
│   ├── raw.rs                     # RAW decoding (rawloader + imagepipe, LibRaw fallback)
│   ├── libraw.rs                   # fallback decoder (LibRaw)
│   └── convert.rs                  # decoding + encoding to the target format
│
├── vendor/
│   └── libraw-sys/              # LibRaw (C++) and its bindings, statically compiled
│
├── nautilus-extension/
│   ├── convert_images_nautilus.py    # nautilus-python extension
│   └── convert-images-gui             # standalone GTK4 GUI
│
├── po/                            # translations (gettext)
│   ├── nautilus-convert-images.pot   # template: source texts, in English
│   ├── fr.po  es.po  de.po           # one translation per language
│   └── update-po.sh                   # regenerates the .pot, updates the .po files
│
├── tests/
│   ├── test_i18n.py                 # catalogs, engine messages, GUI per language
│   ├── test_gui_log.py              # a long log line wraps instead of overflowing
│   ├── test_postinst.py             # install message follows the system language
│   ├── gui_smoke.py                  # launches the real GUI (under Xvfb) and reports
│   ├── gui_log_wrap.py               # measures the log layout in the real GUI
│   └── fedora/                       # tests the .rpm in a real Fedora (podman/docker)
│
└── packaging/
    ├── nautilus-convert-images.desktop
    └── postinst                        # restarts Nautilus after installation (message in en/fr/es/de)
```

## License

GPL-3.0-only. See [LICENSE](LICENSE).

nautilus-convert-images is developed by Gilles MAGNEVILLE. Gilles is not a
professional developer — this project was built with the help of Claude.ai.
