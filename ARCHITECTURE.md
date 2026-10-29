<!-- SPDX-License-Identifier: GPL-3.0-only -->

# nautilus-convert-images Architecture

🇫🇷 [Version française](ARCHITECTURE.fr.md)

This document is the canonical technical contract of nautilus-convert-images.
Where `PROJECT_CONTEXT.md` describes the vision and the principles, this
document defines the exact types, schemas and rules the code must follow. If
the two ever seem to disagree, this document is right for everything concrete
(JSON schema, enumeration values, file paths).

## Overview

> **Nautilus selection → detection → conversion → output files**

```
        +---------------------------+
        |  Nautilus (right-click menu) |
        +--------------+--------------+
                       |  launches as a detached subprocess
                       v
        +---------------------------+
        |   convert-images-gui        |  Python + PyGObject (GTK4)
        |   (graphical interface)     |
        +--------------+--------------+
                       |  drives it as a subprocess,
                       |  parses one JSON line per event
                       v
        +---------------------------+
        | convert-images-engine       |  Rust
        |  detect / convert / formats |
        +---------------------------+
```

The Nautilus extension (`convert_images_nautilus.py`) only collects the
selected paths and launches the GUI: it contains no detection or conversion
logic, so that it can never block or crash Nautilus.

The engine (`convert-images-engine`) knows nothing about Nautilus or GTK: it
is a standalone command-line executable that can be used independently of the
GUI.

---

# Project layout

```
nautilus-convert-images/
├── Cargo.toml
├── Cargo.lock
├── build-deb.sh                 # .deb packaging (fpm)
├── build-rpm.sh                  # .rpm packaging (fpm)
├── README.md                      # English version (shown by default on GitHub)
├── README.fr.md                   # French version
├── PROJECT_CONTEXT.md             # + PROJECT_CONTEXT.fr.md
├── ARCHITECTURE.md                # + ARCHITECTURE.fr.md (this document)
├── CONTRIBUTING.md                # + CONTRIBUTING.fr.md
├── CHANGELOG.md                   # + CHANGELOG.fr.md
├── LICENSE
│
├── src/                          # convert-images-engine (Rust)
│   ├── main.rs                    # CLI entry point, rayon loop, JSON output
│   ├── cli.rs                      # clap: subcommands, recursive file enumeration
│   ├── formats.rs                   # format detection (standard + RAW)
│   ├── raw.rs                        # RAW decoding (rawloader + imagepipe, LibRaw fallback)
│   ├── libraw.rs                      # fallback decoder (LibRaw, static)
│   └── convert.rs                     # source decoding + encoding to the target format
│
├── nautilus-extension/
│   ├── convert_images_nautilus.py    # nautilus-python extension (context menu)
│   └── convert-images-gui             # standalone GTK4 GUI (Python + PyGObject)
│
├── vendor/libraw-sys/             # LibRaw 0.21.3 + bindings (see vendor/README.md)
│
├── po/                            # gettext translations (see "Internationalization")
│   ├── nautilus-convert-images.pot   # template: English source strings
│   ├── fr.po  es.po  de.po           # one translation per language
│   └── update-po.sh                   # regenerates the .pot and updates the .po files
│
├── tests/
│   ├── test_i18n.py                 # catalogs, engine messages, GUI in each language
│   ├── test_gui_log.py              # a long log line wraps
│   ├── test_postinst.py             # the install message follows the system language
│   ├── gui_smoke.py                  # launches the real GUI under Xvfb and reports what it shows
│   ├── gui_log_wrap.py               # measures the log layout in the real GUI
│   └── fedora/                       # tests the .rpm in a real Fedora (podman/docker), see CONTRIBUTING.md
│
└── packaging/
    ├── nautilus-convert-images.desktop  # manual launch of the GUI outside the context menu
    └── postinst                          # restarts Nautilus after the package is installed (message in en/fr/es/de)
```

---

# The engine (`convert-images-engine`)

## Format detection (`formats.rs`)

```rust
enum DetectedFormat {
    Standard(StandardFormat),  // Jpeg | Png | Tiff | Bmp | Gif | WebP
    Raw(String),                // readable label, e.g. "RAW Canon (CR2)"
    Unknown,
}
```

Strategy, in this order:

1. **Known extension** — static table `standard_extension()` /
   `raw_extension_label()`. This resolves the ambiguity between plain TIFF
   and the many RAW formats that are themselves TIFF containers at the
   magic-byte level (CR2, NEF, DNG, ARW, ORF, PEF...).
2. **Content (missing or unknown extension)** — magic-byte sniffing with
   `infer`, limited to the unambiguous standard formats (`image/tiff` is
   deliberately ignored here, for the same reason as in point 1).
3. **Last resort** — an actual RAW decoding attempt
   (`rawloader::decode_file`); on success, the label is built from the
   `make`/`model` read from the file's own metadata.

**Extension point — adding a new RAW format by extension:**
add an entry to `raw_extension_label()` (`formats.rs`). Nothing else needs to
change: the actual decoding depends only on what `rawloader` covers, not on
this table, which is only used for labeling and for filtering during folder
traversal (`has_known_image_extension()`).

## RAW decoding (`raw.rs`)

`rawloader` + `imagepipe` pipeline, always with
`maxwidth = 0, maxheight = 0` (no resizing) and the pipeline's cropping
operations left at their default value (no-op) — see `PROJECT_CONTEXT.md`,
principle no. 2. Two possible outputs:

* `decode_8bit()` → 8 bits/channel RGB (JPEG, BMP, WebP)
* `decode_16bit()` → 16 bits/channel RGB (PNG, TIFF — to preserve all the
  depth the sensor can provide)

**Decoding order and fallback.** For each RAW file:

1. `rawloader` + `imagepipe` (main decoder);
2. if that fails — typically a camera missing from `rawloader`'s database —
   fall back to **LibRaw** (`libraw.rs`);
3. if LibRaw fails too, the errors of both decoders are reported
   ("… ; LibRaw fallback: …") for that file only, and the batch continues.

Each decoder runs under `catch_unwind`: an internal panic (corrupt file)
becomes an error for that file instead of stopping the engine. `imagepipe`
hides the real cause of a failure (it tries `rawloader`, then `image::open`,
and returns "Don't know how to decode image"): `raw.rs` therefore calls
`rawloader::decode_file` again to report its exact error.

LibRaw settings (`libraw.rs`): full resolution (`half_size = 0`, no cropping
or resizing), camera white balance (`use_camera_wb = 1`), sRGB output with
the sRGB curve (`gamm = 1/2.4, 12.92`), no automatic brightness
(`no_auto_bright = 1`), 8 or 16 bits depending on the target format. Unlike
`imagepipe`, which applies a base curve to the luminance (`basecurve`, point
0.50 → 0.60, "to go from linear to a more natural look"), LibRaw applies no
tone curve: the fallback rendering is darker. Neither does lens correction,
sharpening or noise reduction.

Optional LibRaw features that are **not compiled** (`build.rs` defines none
of `USE_JPEG`, `USE_ZLIB`, `USE_X3FTOOLS`, `USE_DNGSDK` or `USE_RAWSPEED`):
the fallback therefore cannot read lossy-compressed (JPEG) DNGs, deflate-
compressed floating-point DNGs, or Sigma Foveon (X3F) files, which
`rawloader` decodes on its own for the models it knows. CR3, absent from
`rawloader`, only goes through LibRaw (`crx.cpp` and `cr3_parser.cpp` are
compiled); it has not been tested on real files. Enabling these options would
require `libjpeg`/`zlib` at build time: to consider if real files demand it.

## Conversion (`convert.rs`)

```rust
enum TargetFormat { Jpeg, Png, Tiff, Bmp, Webp }
```

| Target format | Lossless? | Bit depth | Alpha |
|---|---|---|---|
| PNG | Yes | 8 or 16 bits (inherited from the source) | Kept |
| TIFF | Yes (uncompressed) | 8 or 16 bits (inherited from the source) | Kept |
| BMP | Yes | 8 bits | Kept if present |
| WebP | Yes (VP8L) | 8 bits | Kept if present |
| JPEG | **No** — a limit of the format itself | 8 bits | Not supported (flattened) |

The table above is the source of truth; `TargetFormat::is_lossless()` must
always match it exactly.

**Extension point — adding a new destination format:**

1. Add the variant to `TargetFormat` (`convert.rs`) and its `extension()`.
2. Add the encoding case to `encode_target()`.
3. Add the matching row to the table above **and** to the output of the
   `formats` subcommand (`main.rs`).
4. GUI side: add the entry to `FORMAT_CHOICES`
   (`nautilus-extension/convert-images-gui`).

Nothing else must change — neither the Nautilus extension nor the JSON schema
below.

## Command-line interface (`cli.rs` / `main.rs`)

```
convert-images-engine formats
convert-images-engine detect   [--recursive] <paths...>
convert-images-engine convert  [--recursive] --output-dir <dir> --format <jpeg|png|tiff|bmp|webp>
                                 [--quality <1-100>] [--on-collision <skip|rename|overwrite>]
                                 [--threads <n>] <paths...>
```

Each line written to stdout is a complete JSON object (one line = one
event), so that the GUI can read as it goes without waiting for the process
to finish.

### `detect` events

```json
{"event": "file", "path": "...", "format": "CR2", "is_raw": true}
{"event": "summary", "total": 42, "counts": {"CR2": 30, "JPEG": 12}}
```

### `convert` events

```json
{"event": "start", "total": 42}
{"event": "file_done", "index": 1, "total": 42, "input": "...", "output": "...", "status": "ok"}
{"event": "file_done", "index": 2, "total": 42, "input": "...", "status": "error", "message": "..."}
{"event": "summary", "total": 42, "ok": 40, "errors": 2, "output_dir": "..."}
{"event": "fatal_error", "message": "..."}
```

The `message` fields (failed `file_done` events and `fatal_error`) are
**technical messages in English**, not localized: the GUI translates them
(see "Internationalization"). Likewise, the command-line help and the
engine's error messages are in English. The format labels of the `file`
event (`"format": "RAW Sony (ARW)"`, `"Unknown"`…) are also translated on the
GUI side.

This schema is the contract between the engine and any GUI
(`convert-images-gui` today, possibly something else tomorrow): its shape
must not change without updating this document **and** the code that
consumes it.

### Collision policy (`--on-collision`)

* `skip` — skip the file if the destination already exists.
* `rename` (default) — append ` (1)`, ` (2)`, ... until a free name is
  found.
* `overwrite` — replace the existing file.

---

# The Nautilus extension (`convert_images_nautilus.py`)

Implements `Nautilus.MenuProvider` (`get_file_items` for a selection,
`get_background_items` for a folder's background). It imports nothing heavy
and does no I/O other than writing the list of selected paths to a temporary
file, then launches:

```
convert-images-gui --input-list <temporary file>
```

as a detached subprocess (`start_new_session=True`), without ever waiting for
it to finish. It must be installed under
`/usr/share/nautilus-python/extensions/` — never in `~/.local/...` or
`/usr/local/...`, which are invisible from Nautilus's bwrap sandbox.
The label and tooltip of the menu entry are translated (same gettext domain
as the GUI).

---

# The graphical interface (`convert-images-gui`)

Standalone GTK4 application (it does not need Nautilus to work — it can be
launched manually with paths as arguments). It drives `convert-images-engine`
through `Gio.Subprocess`, reading its standard output line by line
(`Gio.DataInputStream.read_line_async`), never blocking the GTK main loop.
Each JSON line received updates the interface (detection counters, progress
bar, log).

---

# Internationalization

The interface (Nautilus menu entry, window, log) is available in English,
French, Spanish and German, with [gettext](https://www.gnu.org/software/gettext/).

* **English source strings.** The code contains the English messages
  (`_("Convert images")`); English is therefore also the fallback language
  when no translation matches. A single domain, `nautilus-convert-images`, is
  shared by the GUI and the extension.
* **Language selection.** Automatic, through the `gettext` module of Python's
  standard library: `LANGUAGE`, `LC_ALL`, `LC_MESSAGES`, then `LANG`, with
  `fr_CA` falling back to `fr`, then to English (`fallback=True`). No
  `setlocale` and no extra dependency.
* **Catalogs.** `po/<language>.po` (editable sources) are compiled to `.mo`
  by `build-deb.sh` / `build-rpm.sh` (`msgfmt --check`, which rejects a
  modified `{…}` field) and installed to
  `/usr/share/locale/<language>/LC_MESSAGES/nautilus-convert-images.mo`. The
  `.mo` files are not versioned. `release.sh` checks that each package
  contains one `.mo` per language in `po/`.
* **Plurals.** `ngettext` for counts ("1 file detected" / "2 files
  detected"); each language's plural rules are in the header of its `.po`.
* **Named fields.** Messages with variables use `{name}` with `str.format`,
  never `%s`, so that the translator can reorder the words. The
  `# TRANSLATORS:` comments in the code are carried over into the `.pot`.
* **`.desktop` file.** Translated directly with `Name[xx]`,
  `GenericName[xx]`, `Comment[xx]` keys (outside gettext).
* **Development environment variables.**
  `CONVERT_IMAGES_LOCALEDIR` (a catalog folder other than
  `/usr/share/locale`) and `CONVERT_IMAGES_ENGINE` (another engine binary)
  are used by the tests; they have no use in normal operation.

## Install message (`packaging/postinst`)

The script run as root after the package is installed prints a message when
it restarts Nautilus. It does not use gettext (no catalog is available at that
stage, and it must remain a minimal POSIX `sh`): a small `case` block holds
the four texts. The language is chosen by the `pick_language` function, which
reproduces gettext's rules: first non-empty variable among `LANGUAGE`,
`LC_ALL`, `LC_MESSAGES`, `LANG`; `LANGUAGE` may contain several languages
separated by ":" (the first available one wins); `C` and `POSIX` stop the
search; with no match, English. `tests/test_postinst.py` compares this choice
with that of `gettext.find()` for more than thirty configurations.

* **To add a language**: add its pattern to `pick_language` and its text to
  the message `case`, then a marker and test cases in
  `tests/test_postinst.py`.
* The same `pick_language` block is copied into the `postinst.sh` of the
  `raw-thumbs` repository: if the rules change, change both.

## Engine messages

The engine does not know gettext: it emits technical error messages **in
English** in the JSON stream. The GUI renders them in the user's language by
means of `ENGINE_MESSAGE_TEMPLATES`: each template is an English message with
`{name}` fields (for example `"cannot open RAW file: {detail}"`), turned into
a regular expression and translated like any other text.

* The variable parts are kept as they are (file name, text from a
  third-party library) and translated recursively if they in turn match a
  template — this is how the combined error "`cannot open RAW file: …` ;
  `LibRaw fallback: …`" is rendered in full.
* An **unknown** message is displayed as is, in English: changing an engine
  message therefore never breaks the GUI, it just stops being translated.
* **When you change a message in `src/*.rs`**, you must update the matching
  template in the GUI, then run `po/update-po.sh` and translate the new
  entry. `tests/test_i18n.py` checks that every template still exists in the
  Rust code and that the `.pot` is up to date.
* The text returned by `rawloader` or LibRaw ("Couldn't find a decoder for
  this file…") is not translated: it comes from a third-party library.

## Adding or updating a language

See `CONTRIBUTING.md`. In short: `po/update-po.sh` regenerates the `.pot` and
merges the changes into each `.po` (new or modified entries are marked
"fuzzy" or empty); you translate, run `po/update-po.sh` again (which checks
the catalog), then `tests/test_i18n.py`.

---

# Dependency philosophy

* **LibRaw bundled, never installed** — `rawloader` + `imagepipe` (pure
  Rust) remain the main decoder; LibRaw is a safety net and is compiled
  **statically** from `vendor/libraw-sys`: no system library to link against
  or to declare as a package dependency (in contrast with `raw-thumbs`, which
  links `libraw` dynamically). Only `g++` is required at build time;
  `libclang` is not (pre-generated bindings).
* The engine needs no graphical dependency: GTK4 is only required on the
  `convert-images-gui` (Python) side, never on the Rust side.
* Any new Rust dependency must be justified by a clear net benefit — the
  standard library and `image` already cover most needs.

---

# Toolchain note

See the "Toolchain note" section of `README.md` for the pinned crate versions
and why.
