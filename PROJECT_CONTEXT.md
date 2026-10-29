<!-- SPDX-License-Identifier: GPL-3.0-only -->

# PROJECT_CONTEXT.md

🇫🇷 [Version française](PROJECT_CONTEXT.fr.md)

# nautilus-convert-images

**nautilus-convert-images** is an open-source extension for Nautilus (GNOME
Files) that converts images — including camera RAW files — between common
formats, straight from the context menu.

Its goal is to make image conversion as simple as a right-click, without ever
sacrificing image quality or forcing the user to open a terminal or an image
editor.

nautilus-convert-images is aimed at:

* amateur and semi-professional photographers
* Linux/GNOME desktop users in general
* people who receive RAW or TIFF files and just need a JPEG (or the other
  way round) without knowing anything about photography
* administrators who prepare workstations

It is designed to work **entirely locally**: no account, no online service,
no telemetry.

> **Note on this document:** PROJECT_CONTEXT.md defines *why* the project
> exists and *what it values*. It does not redefine the exact data formats
> (the engine's JSON schema, enumerations, the CLI contract) — those live
> once, canonically, in `ARCHITECTURE.md`, so that the two documents cannot
> silently drift apart.

---

# Vision

Most image conversion tools on Linux require either a command line
(`convert`, `dcraw`, `exiftool`...) or a full editing application (darktable,
GIMP) for a task that should be trivial.

nautilus-convert-images aims to answer one simple question:

> **"I selected some photos in my file manager, I want them in another
> format, without losing anything — how?"**

Rather than replacing advanced RAW processing tools such as darktable,
RawTherapee or GIMP, nautilus-convert-images only takes care of raw format
conversion, with no editing, exactly as the camera itself would when
exporting a JPEG from its own screen.

---

# Project philosophy

nautilus-convert-images follows five principles.

## 1. Never lose more than the format requires

PNG, TIFF, BMP and WebP (lossless mode) are re-encoded with no loss of
information whatsoever — verified pixel by pixel. JPEG remains by nature a
lossy format: that cannot be worked around, and the tool never claims
otherwise. The default quality (100) minimizes that loss as much as the
format allows.

## 2. Never crop, never resize

No step of the pipeline crops or reduces the resolution of an image, unless
the user explicitly asks for it — which no current version of the tool
offers. A RAW image is decoded at the exact resolution of the sensor's active
area, identical to what the camera itself would produce.

## 3. Read-only on source files

nautilus-convert-images never modifies or deletes the original file. It:

* reads
* converts
* writes a new file elsewhere (or under a new name)

It never modifies a file in place.

## 4. Fit into the existing workflow, don't create a new one

No new application to learn: the entry point is the Nautilus context menu
the user already knows. The graphical interface only opens on demand, for
this one task.

## 5. Fast

Decoding and encoding use native code (Rust, with C++ LibRaw as a fallback
for RAW files) and take advantage of every available core for batch
conversions. No conversion should feel slower than opening the image in a
viewer.

---

# Project scope

nautilus-convert-images focuses on:

* image format detection (standard and RAW)
* format conversion, without editing
* integration into the Nautilus context menu
* management of the destination folder (including creating a new folder) and
  of file-name collisions

nautilus-convert-images is **not**:

* a RAW editor (no exposure adjustment, manual white balance, curves or
  cropping)
* a replacement for darktable, RawTherapee or GIMP
* a tool for renaming or organizing a photo library
* an online conversion service or a background daemon

---

# Target platforms

Main target: Linux desktop with Nautilus (GNOME Files) 4.x / GTK4.

Targeted distributions:

* Debian
* Ubuntu
* Fedora
* openSUSE
* any GNOME-based distribution with `nautilus-python` available

Architecture: x86_64 first; ARM64 to the extent that the Rust dependencies
used compile there without special adaptation. LibRaw (C++, bundled in
`vendor/` and compiled with `g++`, used as a fallback) should compile there
too, but this has not been verified.

---

# User experience

Using nautilus-convert-images must stay simple:

1. Select files and/or folders in Nautilus.
2. Right-click → **Convert images…** ("Convertir les images…" in French,
   "Convertir imágenes…" in Spanish, "Bilder konvertieren …" in German: the
   language follows the session's)
3. Choose the destination format and the output folder.
4. Convert.

No prior configuration step, no account, no network connection required.

---

# Formats

**Detected source formats**: JPEG, PNG, TIFF, BMP, GIF, WebP, and a wide
range of camera RAW formats (Canon, Nikon, Sony, Adobe DNG, Olympus,
Fujifilm, Panasonic, Pentax, Samsung, Sigma, Hasselblad, Leica, GoPro...).
The exact list of destination formats and their guarantees (lossless or not)
is defined once, in `ARCHITECTURE.md`.

---

# Reliability and transparency

nautilus-convert-images never claims that a conversion is lossless when it is
not (the case of JPEG). When a limit exists, it is documented and displayed,
not hidden.

---

# Extensibility

Adding a new destination or source format must only touch a small number of
well-identified points in the engine, without affecting the Nautilus
extension or the graphical interface. The exact contract (what to add where)
is defined in `ARCHITECTURE.md`.

---

# Performance goals

* Detection: near-instant, even on several thousand files
* Conversion: parallelized across all available cores
* No resident background process once the conversion is finished
* No telemetry, no dependency on an online service

---

# Code principles

* Stable Rust only — no nightly features
* Safe Rust (`unsafe` avoided) for the engine
* Python + PyGObject for the Nautilus integration and the graphical
  interface, which do not need to be compiled native code
* A dependency is only added if it brings a clear net benefit — see
  "Dependency philosophy" in `ARCHITECTURE.md`

---

# Future vision

Future versions might include:

* HEIF/AVIF output support
* pattern-based renaming during batch conversion
* an explicit output color profile (beyond the default sRGB)
* additional interface languages (the interface already exists in English,
  French, Spanish and German: see `CONTRIBUTING.md`)

None of these is required for the tool to be useful. v1 deliberately stays
focused: detection, lossless conversion, Nautilus integration.

---

# Non-goals

nautilus-convert-images will never try to become:

* a full RAW editor
* a photo library manager
* a general-purpose batch processing tool (resizing, watermarking,
  filters...)

It must remain a focused, predictable format conversion tool.

---

# Project values

nautilus-convert-images values:

* fidelity to the source file
* clarity (saying when a format is inherently limited, rather than hiding
  it)
* speed
* ease of integration (a context menu, not a new application to learn)
* transparency about how the tool works and what its limits are

Above all:

**A conversion must never surprise the user — neither through an
unannounced loss of quality, nor through cropping, nor through a reduced
resolution.**
