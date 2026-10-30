<!-- SPDX-License-Identifier: GPL-3.0-only -->

# vendor/

🇫🇷 [Version française](README.fr.md)

## libraw-sys

Copy of [`rsraw-sys` 0.1.1](https://crates.io/crates/rsraw-sys) (MIT
license): the Rust bindings to **LibRaw 0.21.3**, whose C++ source code
is included (`libraw-sys/LibRaw/`, with the `LICENSE.LGPL` and
`LICENSE.CDDL` licenses kept) and compiled **statically** into
`convert-images-engine`. No LibRaw library therefore needs to be installed
on the machine, neither to build nor to run.

LibRaw serves as a **fallback decoder** when `rawloader` cannot read a
file (typically a camera missing from its database) — see
`src/raw.rs` and `ARCHITECTURE.md`, section "RAW decoding".

### Differences from the version published on crates.io

* `build.rs`: the bindings are always taken from the pre-generated file
  `src/bindings.rs`; `bindgen` is no longer called. This avoids requiring
  `libclang` on the build machine. Only a C++ compiler (`g++`, provided
  by `build-essential`) is needed.
* `Cargo.toml`: the build dependency on `bindgen` is removed.

Nothing else is changed.

### Updating LibRaw

Replace the content of `libraw-sys/` with a more recent version of
`rsraw-sys`, re-apply the two changes above, then run `cargo test` (the
tests in `src/libraw.rs` decode a synthetic DNG).
