<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Changelog

Toutes les modifications notables de ce projet sont documentées dans ce fichier.

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/),
et ce projet adhère au [Semantic Versioning](https://semver.org/lang/fr/).

Comme pour linuxdoctor, `VERSION` n'est pas livré avec le code source : il
appartient à votre environnement local, avancé uniquement par vos propres
lancements réussis de `build-deb.sh`/`build-rpm.sh`. Les entrées de ce
changelog utilisent donc une date plutôt qu'un numéro de version.

## [Non publié]

## 2026-09-15

Première version.

### Ajouté

- Moteur de conversion (`convert-images-engine`, Rust) : détection de
  format (JPEG, PNG, TIFF, BMP, GIF, WebP et formats RAW — CR2, CR3, NEF,
  ARW, DNG, ORF, RAF, RW2, PEF, SRW, X3F, etc. — voir `ARCHITECTURE.md`
  pour la liste complète et la stratégie de détection), conversion sans
  perte vers PNG/TIFF/BMP/WebP et vers JPEG à qualité réglable (100 par
  défaut), toujours à pleine résolution et sans recadrage.
- Extension Nautilus (`convert_images_nautilus.py`, nautilus-python) :
  entrée de menu contextuel sur une sélection de fichiers/dossiers et sur
  le fond d'un dossier.
- Interface graphique GTK4 autonome (`convert-images-gui`) : détection en
  temps réel, choix du format de destination, qualité JPEG, dossier de
  destination (avec création de nouveau dossier), politique de collision
  de noms, progression et journal de conversion.
- Empaquetage `.deb` et `.rpm` via `fpm` (`build-deb.sh` / `build-rpm.sh`),
  sur le même modèle que `linuxdoctor` : versionnage interactif ou par
  flag, `VERSION`/`Cargo.toml` mis à jour uniquement après un build
  complet réussi, staging dans un dossier temporaire avec permissions
  normalisées.
- Documentation complète : `README.md`, `PROJECT_CONTEXT.md` (vision et
  principes), `ARCHITECTURE.md` (contrat technique canonique),
  `CONTRIBUTING.md`.

### Choix techniques notables

- Décodage RAW en Rust pur (`rawloader` + `imagepipe`), sans dépendance à
  `libraw` — contrairement à `raw-thumbs` — pour simplifier
  l'empaquetage : aucune bibliothèque C système à lier.
- Binaires installés sous `/usr` (jamais `/usr/local`), leçon directement
  reprise de `raw-thumbs` : le bac à sable bwrap de Nautilus ne monte pas
  `/usr/local`, ce qui rendrait l'extension invisible.
- Certaines versions de crates Rust sont figées dans `Cargo.toml`
  (`clap`, `image`, `imagepipe`, `blake3`, `rayon`, `half`, `exr`, `uuid`,
  `lebe`, `rayon-core`) pour rester compatibles avec un toolchain Rust
  1.75 — voir la section « Toolchain » du `README.md`, même situation que
  documentée dans le changelog de `linuxdoctor` pour `clap` et
  `unicode-segmentation`.
