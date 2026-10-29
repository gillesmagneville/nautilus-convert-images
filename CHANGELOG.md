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

### Modifié

- `release.sh` : quand `VERSION` est déjà publiée (tag local, tag GitHub ou
  release existante), le message d'erreur dit maintenant quoi faire —
  `./build-deb.sh --patch --yes` puis `./build-rpm.sh --no-version-change --yes`
  (ou `--minor` / `--major`) pour passer à la version suivante.

## 2026-10-29 — v1.3.2

### Ajouté

- **Test du paquet `.rpm` dans un vrai Fedora** (`tests/fedora/test-fedora.sh`) :
  lance un conteneur Fedora (podman ou docker), y installe le `.rpm` avec `dnf`,
  vérifie son contenu, le moteur, GTK 4 et l'extension Nautilus (vraies liaisons
  `nautilus-python`), fait tourner l'interface complète sous Xvfb dans les
  quatre langues, puis désinstalle. Si GTK 4 est inutilisable, il identifie le
  paquet manquant. À lancer avant de publier une release (voir
  `CONTRIBUTING.md`).
- Test du script d'installation (`tests/test_postinst.py`) : faux Nautilus,
  langues gérées et non gérées, ordre de priorité des variables, comparaison
  avec le choix réel de `gettext`.

### Modifié

- **Message d'installation dans la langue du système.** Quand l'installation du
  paquet redémarre Nautilus, le message s'affiche en anglais, français,
  espagnol ou allemand selon la langue de la session (mêmes règles que
  l'entrée de menu : `LANGUAGE`, `LC_ALL`, `LC_MESSAGES`, `LANG`), avec repli
  sur l'anglais pour toute autre langue. Il était auparavant uniquement en
  français. Les traductions espagnole et allemande n'ont pas été relues par des
  locuteurs natifs.

## 2026-10-28 — v1.3.1

### Corrigé

- **Paquet `.rpm` : l'interface ne démarrait pas sur une Fedora minimale.**
  GTK 4 a besoin, depuis Python, du fichier d'introspection de `cairo`
  (`cairo-1.0.typelib`), fourni par `gobject-introspection` ; ni `gtk4` ni
  `python3-gobject` ne l'installent. Le menu apparaissait mais un clic ne
  lançait rien. `gobject-introspection` est maintenant déclaré comme
  dépendance, et `release.sh` refuse de publier un `.rpm` qui ne le déclare
  pas. Constaté en installant le `.rpm` de la v1.3.0 dans un vrai Fedora 44
  (conteneur) ; avec la dépendance, l'installation, l'extension Nautilus et
  l'interface dans les quatre langues fonctionnent. Le `.deb` n'était pas
  concerné (il dépend de `gir1.2-gtk-4.0`).
- **Journal de l'interface : les lignes longues passent à la ligne.** Un chemin
  ou un message d'erreur détaillé (de plusieurs centaines de caractères) était
  coupé au bord de la fenêtre et obligeait à faire défiler horizontalement ;
  il est maintenant coupé aux espaces, ou au caractère pour un chemin sans
  espace. Nouveau test `tests/test_gui_log.py`, qui mesure la mise en page dans
  la vraie interface (sous Xvfb).

### Modifié

- **Le README affiché par défaut sur GitHub est maintenant en anglais** :
  `README.md` est la version anglaise et la version française devient
  `README.fr.md` (`README.en.md` disparaît). Les deux sont embarqués dans les
  paquets `.deb` et `.rpm`.
- **Documentation Fedora / RHEL plus juste** : le `.rpm` est testé sur
  Fedora 44 ; la famille RHEL 10 (avec EPEL 10) n'est pas testée ; RHEL, Rocky
  et AlmaLinux 8 et 9 ne sont pas pris en charge (leur `nautilus-python`,
  1.2.3, est trop ancien pour l'API de Nautilus 4).

## 2026-10-28 — v1.3.0

### Ajouté

- **Interface multilingue : anglais, français, espagnol et allemand.** La
  langue est choisie automatiquement d'après la session (`LANGUAGE`,
  `LC_ALL`, `LC_MESSAGES`, `LANG`) et l'anglais sert de langue de repli
  pour toute autre langue. Sont traduits : l'entrée du menu contextuel de
  Nautilus, la fenêtre (libellés, formats, collisions, journal, boîtes de
  dialogue), les messages d'erreur du moteur et le fichier `.desktop`.
  Technique : gettext, domaine `nautilus-convert-images`, catalogues
  `po/*.po` compilés en `.mo` à l'empaquetage et installés dans
  `/usr/share/locale`. Aucune dépendance d'exécution ajoutée.
- `po/update-po.sh` (régénère le modèle `.pot` et met à jour les
  catalogues) et une section « Traduire l'interface » dans
  `CONTRIBUTING.md` pour corriger une traduction ou ajouter une langue.
- Tests Python (`tests/`) : catalogues complets, champs `{…}` identiques à
  la source, contrat des messages moteur ↔ IHM, entrée de menu Nautilus,
  et vraie IHM lancée sous Xvfb dans chaque langue avec le vrai moteur.
- `README.en.md` : section « Languages » ; la mention « interface en
  français uniquement » est supprimée.

### Modifié

- **Les messages du moteur sont désormais en anglais** : champs `message`
  du flux JSON (`file_done` en erreur, `fatal_error`), aide et erreurs de
  `convert-images-engine`. L'IHM les traduit ; un message inconnu s'affiche
  tel quel en anglais. Impact : un script qui lisait ces messages en
  français doit être adapté (le schéma JSON ne change pas).
- `build-deb.sh` et `build-rpm.sh` exigent `msgfmt` (paquet `gettext`) et
  s'arrêtent, `Cargo.toml` restauré, si un catalogue est invalide.
  `release.sh` vérifie que chaque paquet contient une traduction par
  langue de `po/`.

### Notes

- Les traductions espagnole et allemande ont été rédigées avec l'aide de
  Claude et n'ont pas été relues par des locuteurs natifs.
- Le texte d'erreur renvoyé par `rawloader` ou LibRaw reste en anglais
  (bibliothèques tierces).

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
