<!-- SPDX-License-Identifier: GPL-3.0-only -->

# nautilus-convert-images Architecture

Ce document est le contrat technique canonique de nautilus-convert-images.
Là où `PROJECT_CONTEXT.md` décrit la vision et les principes, ce document
définit les types, schémas et règles exacts que le code doit respecter. En
cas de désaccord apparent entre les deux, ce document a raison pour tout ce
qui est concret (schéma JSON, valeurs d'énumération, chemins de fichiers).

## Vue d'ensemble

> **Sélection Nautilus → détection → conversion → fichiers de sortie**

```
        +---------------------------+
        |  Nautilus (menu clic droit) |
        +--------------+--------------+
                       |  lance en sous-processus détaché
                       v
        +---------------------------+
        |   convert-images-gui        |  Python + PyGObject (GTK4)
        |   (interface graphique)     |
        +--------------+--------------+
                       |  pilote en sous-processus,
                       |  parse une ligne JSON par événement
                       v
        +---------------------------+
        | convert-images-engine       |  Rust
        |  detect / convert / formats |
        +---------------------------+
```

L'extension Nautilus (`convert_images_nautilus.py`) ne fait que collecter
les chemins sélectionnés et lancer l'IHM : elle ne contient aucune logique
de détection ni de conversion, pour ne jamais bloquer ni faire planter
Nautilus.

Le moteur (`convert-images-engine`) ne connaît rien de Nautilus ni de
GTK : c'est un exécutable en ligne de commande autonome, utilisable
indépendamment de l'IHM.

---

# Disposition du projet

```
nautilus-convert-images/
├── Cargo.toml
├── Cargo.lock
├── build-deb.sh                 # empaquetage .deb (fpm)
├── build-rpm.sh                  # empaquetage .rpm (fpm)
├── README.md
├── PROJECT_CONTEXT.md
├── ARCHITECTURE.md
├── CONTRIBUTING.md
├── CHANGELOG.md
├── LICENSE
│
├── src/                          # convert-images-engine (Rust)
│   ├── main.rs                    # point d'entrée CLI, boucle rayon, sortie JSON
│   ├── cli.rs                      # clap : sous-commandes, énumération récursive des fichiers
│   ├── formats.rs                   # détection de format (standard + RAW)
│   ├── raw.rs                        # décodage RAW (rawloader + imagepipe, repli LibRaw)
│   ├── libraw.rs                      # décodeur de secours (LibRaw, statique)
│   └── convert.rs                     # décodage source + encodage vers le format cible
│
├── nautilus-extension/
│   ├── convert_images_nautilus.py    # extension nautilus-python (menu contextuel)
│   └── convert-images-gui             # IHM GTK4 autonome (Python + PyGObject)
│
├── vendor/libraw-sys/             # LibRaw 0.21.3 + liaisons (voir vendor/README.md)
│
├── po/                            # traductions gettext (voir « Internationalisation »)
│   ├── nautilus-convert-images.pot   # modèle : textes source en anglais
│   ├── fr.po  es.po  de.po           # une traduction par langue
│   └── update-po.sh                   # régénère le .pot et met à jour les .po
│
├── tests/
│   ├── test_i18n.py                 # catalogues, messages du moteur, IHM par langue
│   └── gui_smoke.py                  # lance la vraie IHM sous Xvfb et rapporte ce qu'elle affiche
│
└── packaging/
    ├── nautilus-convert-images.desktop  # lancement manuel de l'IHM hors menu contextuel
    └── postinst                          # redémarre Nautilus après installation du paquet
```

---

# Le moteur (`convert-images-engine`)

## Détection de format (`formats.rs`)

```rust
enum DetectedFormat {
    Standard(StandardFormat),  // Jpeg | Png | Tiff | Bmp | Gif | WebP
    Raw(String),                // étiquette lisible, ex. "RAW Canon (CR2)"
    Unknown,
}
```

Stratégie, dans cet ordre :

1. **Extension connue** — table statique `standard_extension()` /
   `raw_extension_label()`. Résout l'ambiguïté entre TIFF classique et les
   nombreux formats RAW qui sont eux-mêmes des conteneurs TIFF au niveau
   des octets magiques (CR2, NEF, DNG, ARW, ORF, PEF...).
2. **Contenu (extension absente ou inconnue)** — sniffing par octets
   magiques via `infer`, limité aux formats standards non ambigus
   (`image/tiff` est volontairement ignoré ici, pour la même raison qu'au
   point 1).
3. **Dernier recours** — tentative de décodage RAW réel
   (`rawloader::decode_file`) ; en cas de succès, l'étiquette est
   construite à partir de `make`/`model` lus dans les métadonnées du
   fichier lui-même.

**Point d'extension — ajouter un nouveau format RAW par extension :**
ajouter une entrée dans `raw_extension_label()` (`formats.rs`). Rien
d'autre à modifier : le décodage réel dépend uniquement de la couverture
de `rawloader`, pas de cette table, qui ne sert qu'à l'étiquetage et au
filtrage lors du parcours de dossier (`has_known_image_extension()`).

## Décodage RAW (`raw.rs`)

Pipeline `rawloader` + `imagepipe`, toujours avec
`maxwidth = 0, maxheight = 0` (aucun redimensionnement) et les opérations
de recadrage du pipeline laissées à leur valeur par défaut (no-op) — voir
`PROJECT_CONTEXT.md`, principe n°2. Deux sorties possibles :

* `decode_8bit()` → RGB 8 bits/canal (JPEG, BMP, WebP)
* `decode_16bit()` → RGB 16 bits/canal (PNG, TIFF — pour préserver toute la
  profondeur que le capteur peut fournir)

**Ordre de décodage et repli.** Pour chaque fichier RAW :

1. `rawloader` + `imagepipe` (décodeur principal) ;
2. si cela échoue — typiquement un boîtier absent de la base de
   `rawloader` — repli sur **LibRaw** (`libraw.rs`) ;
3. si LibRaw échoue aussi, l'erreur des deux décodeurs est remontée
   (« … ; repli LibRaw : … ») pour ce fichier seulement, et le lot continue.

Chaque décodeur est exécuté sous `catch_unwind` : une panique interne
(fichier corrompu) devient une erreur de ce fichier au lieu d'arrêter le
moteur. `imagepipe` masque la cause réelle d'un échec (il essaie `rawloader`,
puis `image::open`, et renvoie « Don't know how to decode image ») : `raw.rs`
rappelle donc `rawloader::decode_file` pour remonter son erreur exacte.

Réglages LibRaw (`libraw.rs`) : pleine résolution (`half_size = 0`, aucun
recadrage ni redimensionnement), balance des blancs de l'appareil
(`use_camera_wb = 1`), sortie sRGB avec courbe sRGB (`gamm = 1/2.4, 12.92`),
pas de luminosité automatique (`no_auto_bright = 1`), 8 ou 16 bits selon le
format cible. Contrairement à `imagepipe`, qui applique une courbe de base
sur la luminance (`basecurve`, point 0,50 → 0,60, « pour passer du linéaire
à un aspect plus naturel »), LibRaw n'applique aucune courbe de tons : le
rendu du repli est plus sombre. Ni l'un ni l'autre ne fait de correction
d'objectif, de netteté ni de réduction de bruit.

Options facultatives de LibRaw **non compilées** (`build.rs` ne définit ni
`USE_JPEG`, `USE_ZLIB`, `USE_X3FTOOLS`, `USE_DNGSDK` ni `USE_RAWSPEED`) : le
repli ne lit donc pas les DNG compressés avec perte (JPEG) ni les DNG à
virgule flottante compressés (deflate), ni les Sigma Foveon (X3F), que
`rawloader` décode seul pour les modèles qu'il connaît. Le CR3, absent de
`rawloader`, ne passe que par LibRaw (`crx.cpp` et `cr3_parser.cpp` sont
compilés) ; il n'a pas été testé sur de vrais fichiers. Activer ces options
exigerait `libjpeg`/`zlib` à la compilation : à envisager si des fichiers
réels l'imposent.

## Conversion (`convert.rs`)

```rust
enum TargetFormat { Jpeg, Png, Tiff, Bmp, Webp }
```

| Format cible | Sans perte ? | Profondeur | Alpha |
|---|---|---|---|
| PNG | Oui | 8 ou 16 bits (héritée de la source) | Conservé |
| TIFF | Oui (non compressé) | 8 ou 16 bits (héritée de la source) | Conservé |
| BMP | Oui | 8 bits | Conservé si présent |
| WebP | Oui (VP8L) | 8 bits | Conservé si présent |
| JPEG | **Non** — limite du format lui-même | 8 bits | Non supporté (aplati) |

Le tableau ci-dessus est la source de vérité ; `TargetFormat::is_lossless()`
doit toujours y correspondre exactement.

**Point d'extension — ajouter un nouveau format de destination :**

1. Ajouter la variante dans `TargetFormat` (`convert.rs`) et son
   `extension()`.
2. Ajouter le cas d'encodage dans `encode_target()`.
3. Ajouter la ligne correspondante dans le tableau ci-dessus **et** dans
   la sortie de la sous-commande `formats` (`main.rs`).
4. Côté IHM : ajouter l'entrée dans `FORMAT_CHOICES`
   (`nautilus-extension/convert-images-gui`).

Rien d'autre ne doit changer — ni l'extension Nautilus, ni le schéma JSON
ci-dessous.

## Interface en ligne de commande (`cli.rs` / `main.rs`)

```
convert-images-engine formats
convert-images-engine detect   [--recursive] <chemins...>
convert-images-engine convert  [--recursive] --output-dir <dir> --format <jpeg|png|tiff|bmp|webp>
                                 [--quality <1-100>] [--on-collision <skip|rename|overwrite>]
                                 [--threads <n>] <chemins...>
```

Chaque ligne de sortie sur stdout est un objet JSON complet (une ligne =
un événement), pour que l'IHM puisse lire au fil de l'eau sans attendre la
fin du processus.

### Événements de `detect`

```json
{"event": "file", "path": "...", "format": "CR2", "is_raw": true}
{"event": "summary", "total": 42, "counts": {"CR2": 30, "JPEG": 12}}
```

### Événements de `convert`

```json
{"event": "start", "total": 42}
{"event": "file_done", "index": 1, "total": 42, "input": "...", "output": "...", "status": "ok"}
{"event": "file_done", "index": 2, "total": 42, "input": "...", "status": "error", "message": "..."}
{"event": "summary", "total": 42, "ok": 40, "errors": 2, "output_dir": "..."}
{"event": "fatal_error", "message": "..."}
```

Les champs `message` (événements `file_done` en erreur et `fatal_error`)
sont des **messages techniques en anglais**, non localisés : c'est l'IHM qui
les traduit (voir « Internationalisation »). De même, l'aide en ligne de
commande et les messages d'erreur du moteur sont en anglais. Les libellés
de format de l'événement `file` (`"format": "RAW Sony (ARW)"`, `"Unknown"`…)
sont également traduits côté IHM.

Ce schéma est le contrat entre le moteur et n'importe quelle IHM
(`convert-images-gui` aujourd'hui, potentiellement autre chose demain) : il
ne doit pas changer de forme sans mettre à jour ce document **et** le code
qui le consomme.

### Politique de collision (`--on-collision`)

* `skip` — ignore le fichier si la destination existe déjà.
* `rename` (défaut) — ajoute ` (1)`, ` (2)`, ... jusqu'à trouver un nom
  libre.
* `overwrite` — remplace le fichier existant.

---

# L'extension Nautilus (`convert_images_nautilus.py`)

Implémente `Nautilus.MenuProvider` (`get_file_items` sur une sélection,
`get_background_items` sur le fond d'un dossier). N'importe rien de lourd,
ne fait aucune E/S autre qu'écrire la liste de chemins sélectionnés dans un
fichier temporaire, puis lance :

```
convert-images-gui --input-list <fichier temporaire>
```

en sous-processus détaché (`start_new_session=True`), sans jamais attendre
sa fin. Doit être installée sous
`/usr/share/nautilus-python/extensions/` — jamais dans `~/.local/...` ni
`/usr/local/...`, invisibles depuis le bac à sable bwrap de Nautilus.
Le libellé et l'infobulle de l'entrée de menu sont traduits (même domaine
gettext que l'IHM).

---

# L'interface graphique (`convert-images-gui`)

Application GTK4 autonome (n'a pas besoin de Nautilus pour fonctionner —
elle peut être lancée manuellement avec des chemins en argument). Pilote
`convert-images-engine` via `Gio.Subprocess` en lisant sa sortie standard
ligne par ligne (`Gio.DataInputStream.read_line_async`), jamais en
bloquant la boucle GTK. Chaque ligne JSON reçue met à jour l'interface
(compteurs de détection, barre de progression, journal).

---

# Internationalisation

L'interface (entrée du menu Nautilus, fenêtre, journal) est disponible en
anglais, français, espagnol et allemand, avec [gettext](https://www.gnu.org/software/gettext/).

* **Textes source en anglais.** Le code contient les messages en anglais
  (`_("Convert images")`) ; l'anglais est donc aussi la langue de repli
  quand aucune traduction ne correspond. Un seul domaine,
  `nautilus-convert-images`, est partagé par l'IHM et l'extension.
* **Choix de la langue.** Automatique, par le module `gettext` de la
  bibliothèque standard de Python : `LANGUAGE`, `LC_ALL`, `LC_MESSAGES`,
  puis `LANG`, avec repli de `fr_CA` sur `fr`, puis sur l'anglais
  (`fallback=True`). Aucun `setlocale` ni dépendance supplémentaire.
* **Catalogues.** `po/<langue>.po` (sources éditables) sont compilés en
  `.mo` par `build-deb.sh` / `build-rpm.sh` (`msgfmt --check`, qui refuse
  un champ `{…}` modifié) et installés dans
  `/usr/share/locale/<langue>/LC_MESSAGES/nautilus-convert-images.mo`. Les
  `.mo` ne sont pas versionnés. `release.sh` vérifie que chaque paquet
  contient un `.mo` par langue de `po/`.
* **Pluriels.** `ngettext` pour les comptes (« 1 fichier détecté » / « 2
  fichiers détectés ») ; les règles de pluriel de chaque langue sont dans
  l'en-tête de son `.po`.
* **Champs nommés.** Les messages à variables utilisent `{nom}` avec
  `str.format`, jamais `%s`, pour que le traducteur puisse réordonner les
  mots. Les commentaires `# TRANSLATORS:` du code sont repris dans le `.pot`.
* **Fichier `.desktop`.** Traduit directement avec des clés `Name[xx]`,
  `GenericName[xx]`, `Comment[xx]` (hors gettext).
* **Variables d'environnement de développement.**
  `CONVERT_IMAGES_LOCALEDIR` (dossier de catalogues autre que
  `/usr/share/locale`) et `CONVERT_IMAGES_ENGINE` (autre binaire du moteur)
  servent aux tests ; elles n'ont aucun usage en exploitation normale.

## Messages du moteur

Le moteur ne connaît pas gettext : il émet des messages d'erreur techniques
**en anglais** dans le flux JSON. L'IHM les rend dans la langue de
l'utilisateur au moyen de `ENGINE_MESSAGE_TEMPLATES` : chaque modèle est un
message anglais avec des champs `{nom}` (par exemple
`"cannot open RAW file: {detail}"`), transformé en expression régulière et
traduit comme n'importe quel autre texte.

* Les parties variables sont conservées telles quelles (nom de fichier,
  texte d'une bibliothèque tierce) et traduites récursivement si elles
  correspondent à leur tour à un modèle — c'est ainsi que l'erreur
  combinée « `cannot open RAW file: …` ; `LibRaw fallback: …` » est rendue
  en entier.
* Un message **inconnu** est affiché tel quel, en anglais : modifier un
  message du moteur ne casse donc jamais l'IHM, il cesse seulement d'être
  traduit.
* **Quand on modifie un message dans `src/*.rs`**, il faut mettre à jour
  le modèle correspondant dans l'IHM, puis lancer `po/update-po.sh` et
  traduire la nouvelle entrée. `tests/test_i18n.py` vérifie que chaque
  modèle existe encore dans le code Rust et que le `.pot` est à jour.
* Le texte renvoyé par `rawloader` ou LibRaw (« Couldn't find a decoder for
  this file… ») n'est pas traduit : il vient d'une bibliothèque tierce.

## Ajouter ou mettre à jour une langue

Voir `CONTRIBUTING.md`. En résumé : `po/update-po.sh` régénère le `.pot` et
fusionne les nouveautés dans chaque `.po` (les entrées nouvelles ou
modifiées sont marquées « fuzzy » ou vides) ; on traduit, on relance
`po/update-po.sh` (qui vérifie le catalogue), puis `tests/test_i18n.py`.

---

# Philosophie des dépendances

* **LibRaw embarquée, jamais installée** — `rawloader` + `imagepipe` (Rust
  pur) restent le décodeur principal ; LibRaw sert de secours et est
  compilée **statiquement** depuis `vendor/libraw-sys` : aucune bibliothèque
  système à lier ni à déclarer comme dépendance du paquet (contraste avec
  `raw-thumbs`, qui lie `libraw` dynamiquement). Seul `g++` est requis à la
  compilation ; `libclang` ne l'est pas (liaisons pré-générées).
* Le moteur n'a besoin d'aucune dépendance graphique : GTK4 n'est requis
  que côté `convert-images-gui` (Python), jamais côté Rust.
* Toute nouvelle dépendance Rust doit se justifier par un bénéfice net
  clair — la bibliothèque standard et `image` couvrent déjà l'essentiel.

---

# Note de toolchain

Voir la section « Toolchain » du `README.md` pour les versions de crates
figées et pourquoi.
