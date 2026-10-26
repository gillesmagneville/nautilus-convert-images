<!-- SPDX-License-Identifier: GPL-3.0-only -->

# nautilus-convert-images

Conversion d'images pour Nautilus (GNOME Fichiers) — RAW, JPEG, PNG,
TIFF, BMP, WebP, sans perte de qualité, sans recadrage ni
redimensionnement. Voir `PROJECT_CONTEXT.md` pour la vision et les
principes, `ARCHITECTURE.md` pour le contrat technique (schéma JSON,
formats, points d'extension).

## Status

Version stable, fonctionnelle de bout en bout :

* **Détection de format** — JPEG, PNG, TIFF, BMP, GIF, WebP par extension
  puis, en repli, par analyse du contenu du fichier ; large gamme de
  formats RAW (Canon CR2/CR3, Nikon NEF/NRW, Sony ARW/SRF/SR2, Adobe DNG,
  Olympus ORF, Fujifilm RAF, Panasonic RW2, Pentax PEF, Samsung SRW,
  Sigma X3F, Hasselblad 3FR, Leica RWL, GoPro GPR, etc.), avec repli sur
  une tentative de décodage réel quand l'extension est absente ou
  ambiguë.
* **Conversion** — vers JPEG (qualité réglable, 100 par défaut), PNG,
  TIFF (non compressé), BMP, WebP sans perte (VP8L). PNG, TIFF, BMP et
  WebP sont **authentiquement sans perte**, vérifié par comparaison
  pixel à pixel (y compris canal alpha et profondeur 16 bits). JPEG
  reste par nature un format avec perte — limite du format lui-même, pas
  de cet outil, et jamais présentée comme autre chose.
* **Aucun recadrage, aucun redimensionnement** — les RAW sont décodés à
  pleine résolution (zone active du capteur), sans limite de taille
  appliquée par le pipeline.
* **Extension Nautilus** — entrée de menu contextuel sur une sélection de
  fichiers/dossiers et sur le fond d'un dossier, qui lance l'IHM en
  sous-processus détaché.
* **Interface graphique GTK4** — détection en temps réel, choix du
  format et de la qualité, dossier de destination (avec création d'un
  nouveau dossier), politique de collision de noms, progression et
  journal en direct.
* **Traitement parallèle** (`rayon`) sur tous les cœurs disponibles pour
  les conversions par lot.

Le moteur, l'extension et l'IHM sont découplés (voir `ARCHITECTURE.md`) :
le moteur (`convert-images-engine`) est un exécutable CLI autonome,
utilisable indépendamment de Nautilus ou de GTK.

## Getting set up

```bash
mkdir -p ~/Projects
unzip nautilus-convert-images.zip -d ~/Projects/nautilus-convert-images
cd ~/Projects/nautilus-convert-images
cargo build
```

Dépendances de build pour l'IHM et l'extension (pas seulement le moteur
Rust) :

```bash
sudo apt-get install rustc cargo libgtk-4-dev python3-gi gir1.2-gtk-4.0 \
    python3-nautilus pkg-config build-essential
```

Si vous versionnez ceci avec git, le `.gitignore` exclut déjà `target/`
et les paquets générés (`*.deb`, `*.rpm`) :

```bash
git init
git add .
git commit -m "Scaffold initial : moteur Rust, extension Nautilus, IHM GTK4"
```

## Packaging

Deux scripts construisent des paquets natifs via
[fpm](https://fpm.readthedocs.io/) — `build-deb.sh` (Debian/Ubuntu) et
`build-rpm.sh` (Fedora/RHEL/Rocky/AlmaLinux/openSUSE). Les deux suivent le
même flux : choix d'un incrément de version (interactif ou par flag),
compilation en mode release, staging du moteur + de l'IHM + de
l'extension + de la documentation, puis empaquetage. `VERSION` et
`Cargo.toml` ne sont mis à jour qu'après un build entièrement réussi — une
compilation ou un `fpm` en échec laisse le dépôt inchangé. Une brève
confirmation est demandée avant de construire, sauf si un flag de version
a déjà été fourni sans terminal interactif attaché à stdin (contexte
script/CI — le flag lui-même vaut confirmation) ou si `--yes`/`-y` est
passé explicitement. Lancer sans flag de version et sans terminal
interactif disponible échoue immédiatement avec un message clair, plutôt
que de rester bloqué ou d'échouer silencieusement. Le nom du fichier
`.rpm` généré contient un suffixe `-1` après le numéro de version (ex.
`nautilus-convert-images-1.2.3-1.x86_64.rpm`) — c'est le champ « Release »
du format RPM (distinct de « Version » dans la convention NEVRA), fixé à
1 par défaut par `fpm`. Le format `.deb` n'a pas cette notion, d'où
l'absence de ce suffixe côté `build-deb.sh`. Ni `VERSION` ni `Cargo.toml`
ne contiennent jamais ce suffixe.

```bash
./build-deb.sh --patch   # ou --minor / --major / --no-version-change
./build-rpm.sh --patch
./build-deb.sh --patch --yes   # sans confirmation
./build-deb.sh --clean         # supprime les artefacts de build et les .deb générés
```

Avant la première utilisation, modifiez `MAINTAINER` et `URL` en haut de
chaque script — ce sont des valeurs à personnaliser. Les deux scripts
vérifient la présence des outils requis (`fpm`, `cargo`, et `dpkg-deb` ou
`rpmbuild` respectivement) et expliquent quoi installer si quelque chose
manque — lisez ce message attentivement : sur un « aucun incrément de
version n'a eu lieu » silencieux, la cause la plus probable est un
contrôle d'outil en échec (par exemple `fpm` pas réellement installé — il
s'installe avec `gem install --user-install fpm`, pas un paquet de
distribution) plutôt qu'un bug dans l'arithmétique de version, puisqu'un
incrément n'est jamais écrit avant qu'un build ait entièrement réussi.

**`VERSION` est volontairement absent de cette livraison de code
source.** Comme pour `linuxdoctor`, ce fichier vous appartient
localement : chaque lancement réussi de `build-deb.sh`/`build-rpm.sh` le
fait avancer sur votre machine, en suivant votre propre historique de
build entre deux mises à jour depuis ici. Si `VERSION` (et le champ
`version` correspondant dans `Cargo.toml`) étaient inclus et rafraîchis à
chaque mise à jour des sources, extraire une nouvelle version de code par-
dessus votre projet existant ferait silencieusement reculer votre version
locale à ce que cette livraison a fixé en dernier — aucun des deux
fichiers n'est donc livré ici. Si `VERSION` est totalement absent (une
extraction neuve, sans build local encore fait), les deux scripts
démarrent `CURRENT_VERSION` à `0.1.0` et incrémentent à partir de là.

## Runtime dependencies

Le moteur (`convert-images-engine`) ne dépend d'aucune bibliothèque
externe au-delà de ce que `cargo build` lie statiquement — en particulier
aucune dépendance à `libraw` (voir « Philosophie des dépendances » dans
`ARCHITECTURE.md`). L'IHM et l'extension nécessitent, au moment de
l'exécution : `python3-gi`, `gir1.2-gtk-4.0`, `python3-nautilus` (noms de
paquets Debian/Ubuntu ; `python3-gobject`, `gtk4`, `nautilus-python` sur
Fedora/openSUSE) — déjà déclarés comme dépendances par les deux scripts de
packaging.

## Quickstart

```bash
cargo build --release
./target/release/convert-images-engine formats
./target/release/convert-images-engine detect --recursive ~/Photos
./target/release/convert-images-engine convert --recursive ~/Photos \
    --output-dir ~/Photos/converti --format png
```

Une fois installé (via `.deb`/`.rpm`, ou manuellement — voir
`ARCHITECTURE.md` pour les chemins exacts), la conversion se fait
normalement depuis Nautilus : clic droit sur une sélection ou sur le fond
d'un dossier → **Convertir les images…**. L'IHM peut aussi être lancée
manuellement, hors Nautilus :

```bash
./nautilus-extension/convert-images-gui ~/Photos/img001.cr2 ~/Photos/img002.jpg
```

## Tests

Le moteur a été validé par comparaison pixel à pixel (PNG/TIFF/BMP/WebP
identiques bit à bit à la source, y compris avec canal alpha et
profondeur 16 bits ; JPEG avec un écart minime et attendu à qualité 100),
l'extension Nautilus avec les vraies bibliothèques GObject Introspection,
et l'IHM par un scénario de bout en bout sous Xvfb (détection →
conversion → fichiers produits). Le décodage RAW a, lui, été validé en usage réel avec des fichiers
d'appareils photo.

```bash
cargo build --release && ./target/release/convert-images-engine formats
```

## Toolchain note

Ce projet a été développé et testé avec `rustc`/`cargo` 1.75 (paquet apt
d'Ubuntu 24.04) — la même contrainte que documentée dans le README de
`linuxdoctor` pour `clap`. Plusieurs dépendances sont figées dans
`Cargo.toml` pour cette MSRV :

* `clap` à `4.5.57` — les `clap_builder` plus récents (via `clap_lex`
  1.x) déclarent `edition2024`, qui exige Cargo ≥ 1.85 juste pour être
  analysé.
* `imagepipe` à `=0.5.0` (pas seulement `0.5`) — `0.5.1` dépend d'`image`
  `^0.25`, qui tire `moxcms`, également `edition2024`.
* `image` à `0.24` — la branche `0.25` a le même problème.
* `blake3` à `=1.8.2`, `rayon`/`rayon-core` à `1.10.0`/`1.12.1`, `half` à
  `2.4.1`, `exr` à `1.74.0`, `uuid` à `1.20.0`, `lebe` à `0.5.2` —
  dépendances transitives d'`imagepipe`/`image`, chacune figée à la
  dernière version encore compatible avec Rust 1.75 (MSRV déclarée ou
  `edition2024` requis, selon le cas).

Si vous êtes sur un toolchain plus récent (1.85+), toutes ces contraintes
sont sûres à relâcher — `cargo update` reprendra les versions actuelles
sans aucun changement de code. Ces versions figées compilent et
fonctionnent parfaitement dans l'intervalle : ce n'est pas une limite du
projet, seulement du toolchain de test.

## Layout

```
nautilus-convert-images/
├── .gitignore
├── VERSION                  # absent de cette livraison — voir « Packaging »
├── CHANGELOG.md              # format Keep a Changelog
├── CONTRIBUTING.md            # signaler un bug, ajouter un format, style de code
├── build-deb.sh                 # empaquetage .deb (fpm)
├── build-rpm.sh                   # empaquetage .rpm (fpm)
├── Cargo.toml
├── Cargo.lock
├── README.md
├── PROJECT_CONTEXT.md
├── ARCHITECTURE.md
│
├── src/                       # convert-images-engine (Rust)
│   ├── main.rs                 # point d'entrée CLI, sortie JSON en flux
│   ├── cli.rs                   # clap, énumération récursive des fichiers
│   ├── formats.rs                # détection de format (standard + RAW)
│   ├── raw.rs                     # décodage RAW (rawloader + imagepipe)
│   └── convert.rs                  # décodage + encodage vers le format cible
│
├── nautilus-extension/
│   ├── convert_images_nautilus.py    # extension nautilus-python
│   └── convert-images-gui             # IHM GTK4 autonome
│
└── packaging/
    ├── nautilus-convert-images.desktop
    └── postinst                        # redémarre Nautilus après installation
```

## License

GPL-3.0-only. Voir [LICENSE](LICENSE).

nautilus-convert-images est développé par Gilles MAGNEVILLE. Gilles n'est
pas développeur professionnel — ce projet a été construit avec l'aide de
Claude.ai.
