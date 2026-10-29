<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Contribuer à nautilus-convert-images

🇬🇧 [English version](CONTRIBUTING.md)

Merci de l'intérêt porté à ce projet ! Ce document explique comment
signaler un problème, proposer une amélioration, ou contribuer du code.

## Signaler un bug

Ouvrez une issue en précisant :

- la distribution et la version de Nautilus (`nautilus --version`)
- la commande exacte utilisée, si vous êtes passé par le moteur en ligne
  de commande (`convert-images-engine detect ...` /
  `convert-images-engine convert ...`)
- le format source et le format de destination concernés
- le comportement observé vs attendu
- si possible, la sortie JSON du moteur (`--output-dir` peut être un
  dossier temporaire pour reproduire sans risque sur vos vraies photos)

## Proposer une amélioration

Ouvrez une issue décrivant le besoin avant d'écrire du code, en
particulier pour un nouveau format de destination — voir
`PROJECT_CONTEXT.fr.md` pour ce qui rentre dans le périmètre du projet et ce
qui n'y rentre pas.

## Contribuer du code

1. Forkez le dépôt et créez une branche depuis `main`.
2. Vérifiez que tout passe avant de proposer une pull request :

   ```bash
   cargo build
   cargo fmt --check
   python3 -m py_compile nautilus-extension/convert-images-gui \
                          nautilus-extension/convert_images_nautilus.py
   python3 -m unittest discover -s tests -v
   ```

   Les tests Python ont besoin de `gettext` ; ceux qui lancent la vraie IHM
   demandent en plus PyGObject/GTK4, `xvfb`, ImageMagick et le moteur
   compilé (`cargo build --release`) ; ils sont ignorés si un outil manque.

3. Décrivez dans la pull request ce qui change et pourquoi.

## Ajouter un nouveau format de destination

C'est le type de contribution le plus courant. Le contrat exact (tableau
sans-perte/profondeur/alpha, points de code à modifier) est défini dans
`ARCHITECTURE.fr.md`, section « Ajouter un nouveau format de destination ».
En résumé :

1. `src/convert.rs` — nouvelle variante `TargetFormat` + cas d'encodage.
2. `src/main.rs` — entrée dans la sortie de la sous-commande `formats`.
3. `nautilus-extension/convert-images-gui` — entrée dans `FORMAT_CHOICES`.
4. `ARCHITECTURE.fr.md` — mettre à jour le tableau des formats.

### Règles pour tout nouveau format

- N'annoncez jamais un format comme « sans perte » s'il ne l'est pas
  réellement — voir « Fiabilité et transparence » dans
  `PROJECT_CONTEXT.fr.md`. En cas de doute, vérifiez par comparaison pixel à
  pixel (voir la section « Tests » du `README.fr.md` pour la
  méthode utilisée jusqu'ici).
- Aucun redimensionnement ni recadrage ajouté, même optionnel, sans en
  discuter d'abord dans une issue — c'est un principe fondateur du projet
  (`PROJECT_CONTEXT.fr.md`, principe n°2).

## Traduire l'interface

L'interface existe en anglais (langue de repli), français, espagnol et
allemand. Les traductions espagnole et allemande n'ont pas été relues par
des locuteurs natifs : une relecture est une contribution précieuse, même
pour une seule phrase. Aucune connaissance en programmation n'est
nécessaire — un fichier `po/<langue>.po` est un fichier texte avec, pour
chaque message, `msgid` (l'anglais) et `msgstr` (la traduction).

**Corriger une traduction** : modifiez le `msgstr` dans `po/<langue>.po`,
puis lancez `python3 -m unittest discover -s tests -v`.

**Ajouter une langue** (par exemple l'italien, code `it`) :

```bash
sudo apt install gettext      # msgmerge, msgfmt
msginit --no-translator --locale=it -i po/nautilus-convert-images.pot -o po/it.po
# traduire po/it.po avec un éditeur de texte ou Poedit, puis :
./po/update-po.sh
python3 -m unittest discover -s tests -v
```

Pour essayer le résultat sans installer le paquet :

```bash
mkdir -p /tmp/locale/it/LC_MESSAGES
msgfmt -o /tmp/locale/it/LC_MESSAGES/nautilus-convert-images.mo po/it.po
CONVERT_IMAGES_LOCALEDIR=/tmp/locale LANGUAGE=it \
  CONVERT_IMAGES_ENGINE=./target/release/convert-images-engine \
  python3 nautilus-extension/convert-images-gui ~/Photos
```

À respecter :

- Un catalogue doit être **complet** (aucune entrée vide ni « fuzzy ») pour
  passer les tests : un catalogue à moitié traduit afficherait une
  interface mélangeant deux langues.
- Gardez les champs entre accolades (`{ok}`, `{folder}`…) **exactement** tels
  quels : on peut les déplacer dans la phrase, pas les renommer ni les
  traduire. `msgfmt --check` (lancé par `po/update-po.sh` et par les scripts
  de paquet) refuse un catalogue qui ne respecte pas cette règle.
- Lisez les commentaires `#.` (« TRANSLATORS ») au-dessus de certains
  messages : ils expliquent le contexte.
- Une nouvelle langue est prise en compte automatiquement par
  `build-deb.sh`, `build-rpm.sh` et `release.sh` dès que `po/<langue>.po`
  existe ; ajoutez aussi les clés `Name[it]`, `GenericName[it]` et
  `Comment[it]` dans `packaging/nautilus-convert-images.desktop`, et la
  langue dans le test `GuiSmokeTests` si vous voulez la couvrir.
- Si vous ajoutez ou modifiez un texte dans le code : écrivez-le en
  anglais avec `_("…")`, lancez `po/update-po.sh`, et traduisez les entrées
  nouvelles (au minimum en français, langue de l'auteur). Voir
  « Internationalisation » dans `ARCHITECTURE.fr.md`, notamment pour les
  messages du moteur.

## Tester le paquet `.rpm` dans un vrai Fedora

Avant de publier une release, le `.rpm` se teste dans un vrai Fedora, sans rien
installer sur votre machine, grâce à un conteneur (podman ou docker) :

```bash
sudo apt install podman                 # une seule fois
tests/fedora/test-fedora.sh             # prend le .rpm présent à la racine du dépôt
tests/fedora/test-fedora.sh nautilus-convert-images-X.Y.Z-1.x86_64.rpm 43   # autre fichier, autre version de Fedora
```

Le script installe le paquet avec `dnf` (c'est Fedora qui résout les
dépendances), vérifie son contenu, lance le moteur, contrôle GTK 4 et
l'extension Nautilus avec les vraies liaisons de `nautilus-python`, fait tourner
l'interface complète sous Xvfb dans les quatre langues, puis désinstalle. Il
se termine par `RÉSULTAT : TOUT EST OK` (suivi du nombre de vérifications réussies).

Si GTK 4 est inutilisable, le test cherche tout seul quel paquet Fedora manque
et le signale (`DÉPENDANCE MANQUANTE AU PAQUET`) : c'est ainsi qu'a été trouvée
la dépendance `gobject-introspection`, ajoutée en v1.3.1.

Ce test a besoin du réseau (image Fedora, paquets `dnf`) : il n'est pas lancé
par `unittest discover`. Il valide l'installation et l'interface, mais pas un
clic réel dans une session Nautilus ; il ne remplace donc pas un essai sur un
bureau Fedora.

## Style de code

- `cargo fmt` avant de proposer une pull request.
- Rust stable uniquement, pas de fonctionnalités nightly.
- Le moteur (`src/`) ne doit jamais dépendre de GTK ni de Nautilus — voir
  « Vue d'ensemble » dans `ARCHITECTURE.fr.md`.
- Toute nouvelle dépendance doit se justifier (voir « Philosophie des
  dépendances » dans `ARCHITECTURE.fr.md`).
- Si une dépendance doit être figée à une version précise pour rester
  compatible avec un toolchain Rust plus ancien, documentez pourquoi en
  commentaire dans `Cargo.toml`, comme les entrées déjà présentes.

## Documentation

Si votre changement modifie le comportement observable (nouveau format,
nouvelle option CLI, nouveau schéma JSON, nouveau texte d'interface),
mettez à jour `CHANGELOG.md` et `CHANGELOG.fr.md` dans la même pull request,
sous `[Unreleased]` (`[Non publié]` dans le fichier français), et
`ARCHITECTURE.md` / `ARCHITECTURE.fr.md` si le contrat technique change.

Chaque document existe en deux langues : l'anglais (`README.md`,
`PROJECT_CONTEXT.md`, `ARCHITECTURE.md`, `CONTRIBUTING.md`, `CHANGELOG.md`,
affiché par défaut sur GitHub) et le français (les mêmes noms avec
`.fr.md`). Si vous modifiez l'un, modifiez aussi l'autre. Si vous n'écrivez
que dans une langue, dites-le dans la pull request : le mainteneur traduira.

Les notes de release sont publiées en anglais d'abord, puis en français. Elles
viennent de l'entrée du jour de `CHANGELOG.md` et de `CHANGELOG.fr.md` ;
`release.sh` refuse de publier si l'un des deux fichiers ne l'a pas.

## Questions

Pour toute question qui ne rentre pas dans les cas ci-dessus, ouvrez
simplement une issue.

## Licence

En contribuant, vous acceptez que vos contributions soient publiées sous
la même licence que le projet (GPL-3.0-only).
