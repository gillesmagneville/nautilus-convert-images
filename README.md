<!-- SPDX-License-Identifier: GPL-3.0-only -->

# nautilus-convert-images

**Convertissez vos photos d'un clic droit, directement depuis Nautilus —
RAW compris, sans perte, sans recadrage ni redimensionnement.**

[![Dernière release](https://img.shields.io/github/v/release/gillesmagneville/nautilus-convert-images)](https://github.com/gillesmagneville/nautilus-convert-images/releases/latest)
[![Licence GPL-3.0](https://img.shields.io/badge/licence-GPL--3.0-blue)](LICENSE)

Sélectionnez des fichiers ou des dossiers entiers dans GNOME Fichiers,
clic droit → **Convertir les images…**, choisissez le format et le dossier
de destination : c'est tout. Voir `PROJECT_CONTEXT.md` pour la vision et
les principes, `ARCHITECTURE.md` pour le contrat technique.

## Pourquoi l'utiliser ?

* **Aucun détour** — pas d'application à lancer, pas de ligne de commande,
  pas d'import : la conversion est dans le menu contextuel de vos fichiers.
* **Tout ce que vous avez sous la main** — RAW (Canon, Nikon, Sony,
  Fujifilm, Olympus, Panasonic, Pentax, Sigma, Adobe DNG…), JPEG, PNG,
  TIFF, BMP, GIF, WebP, y compris mélangés dans un même dossier : le format
  de chaque fichier est détecté, même quand l'extension est absente ou
  trompeuse.
* **Votre qualité, intacte** — pleine résolution, jamais de recadrage ni de
  redimensionnement ; PNG, TIFF, BMP et WebP sont réellement sans perte
  (transparence et profondeur 16 bits conservées).
* **Rapide** — moteur en Rust, tous les cœurs du processeur travaillent en
  parallèle sur les lots.
* **Sous contrôle** — vous voyez ce qui a été détecté avant de lancer,
  choisissez le dossier de destination (création possible) et ce qui se
  passe si un nom existe déjà (ignorer, renommer, écraser), puis suivez la
  progression en direct.
* **Léger et libre** — décodeurs RAW intégrés au programme (rien à
  installer en plus), licence GPL-3.0.

| Vous avez | Vous voulez | Il suffit de |
|---|---|---|
| Un dossier de RAW après un shooting | Des JPEG à partager | le sélectionner, choisir JPEG (le choix par défaut) |
| Des RAW à archiver | Un format sans perte | choisir TIFF ou PNG |
| Un dossier qui mélange CR2, TIFF et PNG | Un seul format partout | tout sélectionner, choisir le format |
| Des BMP ou PNG volumineux | Des fichiers plus compacts, sans perte | choisir WebP sans perte |

## Installation

Téléchargez le paquet de votre distribution depuis la page des
[releases](https://github.com/gillesmagneville/nautilus-convert-images/releases/latest)
(`X.Y.Z` = numéro de version), puis :

```bash
# Debian, Ubuntu et dérivés
sudo apt install ./nautilus-convert-images_X.Y.Z_amd64.deb

# Fedora, RHEL et dérivés (nautilus-python vient d'EPEL sur RHEL/Rocky/Alma)
sudo dnf install ./nautilus-convert-images-X.Y.Z-1.x86_64.rpm
```

Nautilus est redémarré automatiquement pour activer l'entrée de menu.
Chaque paquet est publié avec son propre fichier `.sha256` (il n'y a pas
de `SHA256SUMS` global). Pour vérifier un téléchargement, placez le paquet
et son fichier `.sha256` dans le même dossier :

```bash
sha256sum -c nautilus-convert-images_X.Y.Z_amd64.deb.sha256
```

## Utilisation

Clic droit sur une sélection (fichiers et/ou dossiers) ou sur le fond d'un
dossier → **Convertir les images…**. L'IHM peut aussi être lancée
manuellement, hors Nautilus :

```bash
convert-images-gui ~/Photos/img001.cr2 ~/Photos/img002.jpg
```

## Formats

| | Formats |
|---|---|
| **Sources** | RAW (CR2/CR3, NEF/NRW, ARW/SRF/SR2, DNG, ORF, RAF, RW2, PEF, SRW, X3F, 3FR, RWL, GPR…), JPEG, PNG, TIFF, BMP, GIF, WebP |
| **Destinations** | JPEG (qualité réglable, 100 par défaut), PNG, TIFF (non compressé), BMP, WebP sans perte (VP8L) |

PNG, TIFF, BMP et WebP sont **authentiquement sans perte**, vérifié par
comparaison pixel à pixel (canal alpha et 16 bits compris). JPEG reste par
nature un format avec perte — limite du format lui-même, pas de cet outil,
et jamais présentée comme autre chose. La détection se fait par extension,
puis par analyse du contenu, avec en dernier recours une tentative de
décodage réel. Les RAW sont décodés à pleine résolution (zone active du
capteur).

**Décodage RAW :** `rawloader` d'abord ; si le fichier ne peut pas être lu
(typiquement un boîtier absent de sa base), repli automatique sur
[LibRaw](https://www.libraw.org/), embarquée dans le programme. Si les deux
échouent, l'erreur est affichée pour ce fichier et le lot continue avec le
suivant. Le rendu du repli est neutre (balance des blancs de l'appareil,
sRGB, sans courbe de contraste ni correction d'objectif) : il paraît donc
moins contrasté que l'aperçu JPEG du boîtier, aux coins plus sombres, et peut
différer légèrement du décodeur principal.

Le moteur, l'extension et l'IHM sont découplés (voir `ARCHITECTURE.md`) :
le moteur (`convert-images-engine`) est un exécutable CLI autonome,
utilisable indépendamment de Nautilus ou de GTK.

## Getting set up

Pour compiler depuis les sources :

```bash
git clone https://github.com/gillesmagneville/nautilus-convert-images.git ~/Projects/nautilus-convert-images
cd ~/Projects/nautilus-convert-images
cargo build
```

Dépendances de build pour l'IHM et l'extension (pas seulement le moteur
Rust) :

```bash
sudo apt-get install rustc cargo libgtk-4-dev python3-gi gir1.2-gtk-4.0 \
    python3-nautilus pkg-config build-essential
```

`build-essential` fournit `g++`, nécessaire pour compiler LibRaw (C++)
embarquée dans `vendor/` : la première compilation est donc plus longue
(quelques minutes), les suivantes sont incrémentales.

## Packaging

Deux scripts construisent des paquets natifs via
[fpm](https://fpm.readthedocs.io/) — `build-deb.sh` (Debian/Ubuntu) et
`build-rpm.sh` (Fedora/RHEL/Rocky/AlmaLinux). Les deux suivent le même
flux : choix d'un incrément de version (interactif ou par flag),
compilation en mode release, staging du moteur + de l'IHM + de l'extension
+ de la documentation, puis empaquetage. `VERSION` et `Cargo.toml` ne sont
mis à jour qu'après un build entièrement réussi — une compilation ou un
`fpm` en échec laisse le dépôt inchangé. Une brève confirmation est
demandée avant de construire, sauf si un flag de version a déjà été fourni
sans terminal interactif attaché à stdin (contexte script/CI — le flag
lui-même vaut confirmation) ou si `--yes`/`-y` est passé explicitement.
Lancer sans flag de version et sans terminal interactif disponible échoue
immédiatement avec un message clair. Le nom du fichier `.rpm` généré
contient un suffixe `-1` après le numéro de version (ex.
`nautilus-convert-images-1.2.3-1.x86_64.rpm`) — c'est le champ « Release »
du format RPM, fixé à 1 par défaut par `fpm`. Le format `.deb` n'a pas
cette notion. Ni `VERSION` ni `Cargo.toml` ne contiennent jamais ce suffixe.

```bash
./build-deb.sh --patch   # ou --minor / --major / --no-version-change
./build-rpm.sh --patch
./build-deb.sh --patch --yes   # sans confirmation
./build-deb.sh --clean         # supprime les artefacts de build et les .deb générés
```

`MAINTAINER` et `URL`, en haut de chaque script, sont déjà renseignés pour
ce dépôt ; adaptez-les dans un fork. Les deux scripts vérifient la présence
des outils requis (`fpm`, `cargo`, et `dpkg-deb` ou `rpmbuild`
respectivement) et expliquent quoi installer si quelque chose manque —
lisez ce message attentivement : sur un « aucun incrément de version n'a eu
lieu » silencieux, la cause la plus probable est un contrôle d'outil en
échec (par exemple `fpm` pas réellement installé — il s'installe avec
`gem install --user-install fpm`, pas un paquet de distribution), puisqu'un
incrément n'est jamais écrit avant qu'un build ait entièrement réussi.

`VERSION` est versionné avec le code : il correspond au tag de la dernière
release.

### Publier une release

Après les builds habituels (`VERSION` à jour, `.deb` et `.rpm` générés),
`release.sh` publie la release GitHub correspondante : contrôles
préalables, reconstruction des paquets si nécessaire, commit et push de
`main`, puis création de la release avec les deux paquets et un fichier
`.sha256` par paquet. Il nécessite [`gh`](https://cli.github.com/)
authentifié.

```bash
./release.sh --dry-run   # aperçu, rien n'est modifié ni publié
./release.sh
```

## Runtime dependencies

Le moteur (`convert-images-engine`) ne dépend d'aucune bibliothèque
externe au-delà de ce que `cargo build` lie statiquement — en particulier
aucune bibliothèque LibRaw à installer : elle est embarquée statiquement
(voir « Philosophie des dépendances » dans `ARCHITECTURE.md`). L'IHM et l'extension nécessitent, au moment de
l'exécution : `python3-gi`, `gir1.2-gtk-4.0`, `python3-nautilus` (noms de
paquets Debian/Ubuntu ; `python3-gobject`, `gtk4`, `nautilus-python` sur
Fedora) — déjà déclarés comme dépendances par les deux scripts de
packaging.

## Quickstart

Le moteur s'utilise aussi seul, en ligne de commande :

```bash
cargo build --release
./target/release/convert-images-engine formats
./target/release/convert-images-engine detect --recursive ~/Photos
./target/release/convert-images-engine convert --recursive ~/Photos \
    --output-dir ~/Photos/converti --format png
```

## Tests

Le moteur a été validé par comparaison pixel à pixel (PNG/TIFF/BMP/WebP
identiques bit à bit à la source, y compris avec canal alpha et
profondeur 16 bits ; JPEG avec un écart minime et attendu à qualité 100),
l'extension Nautilus avec les vraies bibliothèques GObject Introspection,
et l'IHM par un scénario de bout en bout sous Xvfb (détection →
conversion → fichiers produits). Le repli LibRaw est couvert par des
tests unitaires (`cargo test`) sur un DNG synthétique, et a été vérifié sur
de vrais fichiers `.arw` du Sony DSC-RX100M6 (absent de la base de
`rawloader`) ; la fidélité sur les autres appareils est validée au cas par
cas.

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
├── VERSION                  # version courante (= tag de la dernière release)
├── CHANGELOG.md              # format Keep a Changelog
├── CONTRIBUTING.md            # signaler un bug, ajouter un format, style de code
├── build-deb.sh                 # empaquetage .deb (fpm)
├── build-rpm.sh                   # empaquetage .rpm (fpm)
├── release.sh                       # publication de la release GitHub
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
│   ├── raw.rs                     # décodage RAW (rawloader + imagepipe, repli LibRaw)
│   ├── libraw.rs                   # décodeur de secours (LibRaw)
│   └── convert.rs                  # décodage + encodage vers le format cible
│
├── vendor/
│   └── libraw-sys/              # LibRaw (C++) et ses liaisons, compilée statiquement
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
