<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Contribuer à nautilus-convert-images

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
`PROJECT_CONTEXT.md` pour ce qui rentre dans le périmètre du projet et ce
qui n'y rentre pas.

## Contribuer du code

1. Forkez le dépôt et créez une branche depuis `main`.
2. Vérifiez que tout passe avant de proposer une pull request :

   ```bash
   cargo build
   cargo fmt --check
   python3 -m py_compile nautilus-extension/convert-images-gui \
                          nautilus-extension/convert_images_nautilus.py
   ```

3. Décrivez dans la pull request ce qui change et pourquoi.

## Ajouter un nouveau format de destination

C'est le type de contribution le plus courant. Le contrat exact (tableau
sans-perte/profondeur/alpha, points de code à modifier) est défini dans
`ARCHITECTURE.md`, section « Ajouter un nouveau format de destination ».
En résumé :

1. `src/convert.rs` — nouvelle variante `TargetFormat` + cas d'encodage.
2. `src/main.rs` — entrée dans la sortie de la sous-commande `formats`.
3. `nautilus-extension/convert-images-gui` — entrée dans `FORMAT_CHOICES`.
4. `ARCHITECTURE.md` — mettre à jour le tableau des formats.

### Règles pour tout nouveau format

- N'annoncez jamais un format comme « sans perte » s'il ne l'est pas
  réellement — voir « Fiabilité et transparence » dans
  `PROJECT_CONTEXT.md`. En cas de doute, vérifiez par comparaison pixel à
  pixel (voir la section « État des tests » du `README.md` pour la
  méthode utilisée jusqu'ici).
- Aucun redimensionnement ni recadrage ajouté, même optionnel, sans en
  discuter d'abord dans une issue — c'est un principe fondateur du projet
  (`PROJECT_CONTEXT.md`, principe n°2).

## Style de code

- `cargo fmt` avant de proposer une pull request.
- Rust stable uniquement, pas de fonctionnalités nightly.
- Le moteur (`src/`) ne doit jamais dépendre de GTK ni de Nautilus — voir
  « Vue d'ensemble » dans `ARCHITECTURE.md`.
- Toute nouvelle dépendance doit se justifier (voir « Philosophie des
  dépendances » dans `ARCHITECTURE.md`).
- Si une dépendance doit être figée à une version précise pour rester
  compatible avec un toolchain Rust plus ancien, documentez pourquoi en
  commentaire dans `Cargo.toml`, comme les entrées déjà présentes.

## Documentation

Si votre changement modifie le comportement observable (nouveau format,
nouvelle option CLI, nouveau schéma JSON), mettez à jour `CHANGELOG.md`
dans la même pull request, sous `[Non publié]`, et `ARCHITECTURE.md` si le
contrat technique change.

## Questions

Pour toute question qui ne rentre pas dans les cas ci-dessus, ouvrez
simplement une issue.

## Licence

En contribuant, vous acceptez que vos contributions soient publiées sous
la même licence que le projet (GPL-3.0-only).
