<!-- SPDX-License-Identifier: GPL-3.0-only -->

# vendor/

🇬🇧 [English version](README.md)

## libraw-sys

Copie de [`rsraw-sys` 0.1.1](https://crates.io/crates/rsraw-sys) (licence
MIT) : les liaisons Rust vers **LibRaw 0.21.3**, dont le code source C++
est inclus (`libraw-sys/LibRaw/`, licences `LICENSE.LGPL` et
`LICENSE.CDDL` conservées) et compilé **statiquement** dans
`convert-images-engine`. Aucune bibliothèque LibRaw n'est donc à installer
sur la machine, ni pour compiler ni pour exécuter.

LibRaw sert de **décodeur de secours** quand `rawloader` ne peut pas lire
un fichier (typiquement un boîtier absent de sa base) — voir
`src/raw.rs` et `ARCHITECTURE.fr.md`, section « Décodage RAW ».

### Différences avec la version publiée sur crates.io

* `build.rs` : les liaisons sont toujours reprises du fichier pré-généré
  `src/bindings.rs` ; `bindgen` n'est plus appelé. Cela évite d'exiger
  `libclang` sur la machine de build. Seul un compilateur C++ (`g++`,
  fourni par `build-essential`) est nécessaire.
* `Cargo.toml` : la dépendance de build à `bindgen` est retirée.

Rien d'autre n'est modifié.

### Mettre à jour LibRaw

Remplacer le contenu de `libraw-sys/` par une version plus récente de
`rsraw-sys`, ré-appliquer les deux modifications ci-dessus, puis lancer
`cargo test` (les tests de `src/libraw.rs` décodent un DNG synthétique).
