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

## 2026-10-27 — v1.2.0

### Ajouté

- **Repli LibRaw** pour les fichiers RAW que `rawloader` ne sait pas lire,
  typiquement un boîtier absent de sa base (cas rencontré avec les `.arw`
  du Sony DSC-RX100M6, refusés jusque-là). Ordre : `rawloader`/`imagepipe`
  d'abord, LibRaw ensuite, et si les deux échouent l'erreur est affichée
  pour ce fichier et le lot continue.
- LibRaw 0.21.3 est embarquée et compilée statiquement
  (`vendor/libraw-sys`) : aucune bibliothèque à installer, aucune
  dépendance ajoutée aux paquets `.deb`/`.rpm`. Seul `g++` est requis à la
  compilation (la première compilation est plus longue).
- Tests unitaires du décodage (`cargo test`) avec un DNG synthétique
  généré à la volée.

### Corrigé

- Un RAW refusé affichait le message générique d'`imagepipe` (« Don't know
  how to decode image ») qui masquait la vraie cause ; l'erreur exacte de
  `rawloader` est maintenant remontée.
- Une panique interne d'un décodeur sur un fichier corrompu arrêtait tout
  le moteur ; elle est maintenant convertie en erreur pour ce seul fichier.

### Changé

- Documentation : le choix « pas de `libraw` » est remplacé par « LibRaw
  embarquée en secours » (voir `ARCHITECTURE.md`, « Philosophie des
  dépendances »), et l'état de la prise en charge RAW est précisé.

## 2026-10-27 — v1.1.1

Version de maintenance : aucun changement fonctionnel (le moteur,
l'extension Nautilus et l'IHM sont identiques à la version précédente).

### Ajouté

- `release.sh` : publication de la release GitHub (contrôles préalables,
  reconstruction des paquets si nécessaire, commit et push, création de la
  release avec les deux paquets et leurs fichiers `.sha256`).

### Changé

- `README.md` : présentation orientée usage (pourquoi l'utiliser, cas
  d'usage, formats pris en charge), installation par paquets `.deb`/`.rpm`
  et vérification des téléchargements ; retrait des passages obsolètes
  (livraison par archive, `VERSION` « absent »).
- Publication : chaque paquet est publié avec son propre fichier `.sha256`
  (il n'y a plus de `SHA256SUMS` global).

## 2026-10-26

Première release stable publiée sur GitHub (tag `v1.1.0`, paquets `.deb` et `.rpm`).

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
- Bouton « Quitter » dans l'IHM, toujours visible (y compris pendant la
  détection, avant que le reste des options n'apparaisse). Intercepte
  aussi la fermeture par la croix de la fenêtre (`close-request`) pour
  appliquer la même règle. Si une conversion est en cours au moment de
  quitter, une boîte de dialogue (`Gtk.AlertDialog`) avertit que les
  fichiers déjà convertis resteront sur le disque mais que les suivants
  ne seront pas traités, avec un choix explicite « Annuler » (par
  défaut) / « Quitter quand même » ; sans conversion en cours, la
  fermeture est immédiate, sans dialogue.

### Changé

- Format de destination sélectionné par défaut dans l'IHM : JPEG au lieu
  de PNG (demande explicite ; PNG reste évidemment disponible dans le
  menu déroulant).

### Corrigé

- Bug signalé : l'entrée de menu n'apparaissait pas du tout dans Nautilus.
  Cause identifiée et confirmée par reproduction (`nautilus` lancé depuis
  un terminal affichait la trace) : `convert_images_nautilus.py` figeait
  `gi.require_version("Nautilus", "4.0")`, alors que sur la machine de
  l'utilisateur (une version de Nautilus plus récente que celle du bac à
  sable de développement) seul le typelib `Nautilus-4.1` est installé —
  `4.0` n'existe simplement pas sur ce système. Le même figeage aurait de
  toute façon posé problème même si `4.0` avait existé : au moment où le
  fichier s'exécute, le processus Nautilus hôte a déjà chargé son propre
  typelib (`gi.require_version` ne peut plus changer une version déjà
  chargée pour le processus), donc toute version figée ici autre que
  celle réellement en cours aurait échoué avec « already loaded with
  version X ». Corrigé en retirant complètement le figeage de version
  pour `Nautilus` (celui de `GObject`, lui, ne pose aucun risque : une
  seule version d'introspection existe pour ce namespace). Vérifié que
  l'extension se charge sans erreur à la fois quand `Nautilus` n'est pas
  encore chargé du tout et quand il l'est déjà à une version donnée.

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
