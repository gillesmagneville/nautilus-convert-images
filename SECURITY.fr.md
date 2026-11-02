<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Politique de sécurité

🇬🇧 [English version](SECURITY.md)

nautilus-convert-images est maintenu par une seule personne, à titre bénévole. Cette page explique comment signaler un problème de sécurité et ce que vous pouvez en attendre.

## Versions prises en charge

Seule la **dernière version publiée** reçoit les correctifs de sécurité. Si vous utilisez une version plus ancienne, mettez-la d'abord à jour : les paquets sont sur la page des [Releases](https://github.com/gillesmagneville/nautilus-convert-images/releases) et les changements sont listés dans le [CHANGELOG](CHANGELOG.fr.md).

## Signaler une vulnérabilité

**Merci de ne pas signaler une vulnérabilité dans une issue, une pull request ou une discussion publique** : n'importe qui pourrait la lire avant qu'un correctif existe.

Signalez-la en privé, de l'une de ces deux façons :

1. **Sur GitHub** : ouvrez l'[onglet Security](https://github.com/gillesmagneville/nautilus-convert-images/security) du dépôt et cliquez sur **Report a vulnerability**. Seuls vous et le mainteneur voyez le signalement.
2. **Par courriel** : écrivez à [gilles@magneville.fr](mailto:gilles@magneville.fr) avec l'objet « nautilus-convert-images sécurité ».

Indiquez, autant que possible :

- la version du paquet (`dpkg -s nautilus-convert-images` ou `rpm -q nautilus-convert-images`), votre distribution et la version de Nautilus (`nautilus --version`) ;
- la description du problème et les étapes pour le reproduire ;
- l'impact que vous lui voyez ;
- si le problème vient d'un fichier particulier, ce fichier — seulement si vous avez le droit de le partager.

## Ce que vous pouvez attendre

Ce sont des objectifs, pas des garanties, puisqu'il n'y a qu'un seul mainteneur :

- un accusé de réception de votre signalement sous **7 jours** ;
- une réponse indiquant s'il est considéré comme une vulnérabilité, puis des nouvelles au moins toutes les quelques semaines jusqu'à ce que le sujet soit réglé ;
- un correctif publié dans une **nouvelle version**, mentionné dans le CHANGELOG ; pour un problème grave, un avis de sécurité GitHub également ;
- vous êtes cité dans les notes de version, sauf si vous préférez rester anonyme.

Merci de garder les détails confidentiels jusqu'à la publication d'une version corrigée, pour que les utilisateurs aient le temps de mettre à jour.

## Ce qui est concerné

nautilus-convert-images travaille sur votre ordinateur, sur vos propres photos, et ne les envoie nulle part. Il **lit en revanche des fichiers image qui peuvent venir de n'importe où** (un téléchargement, un courriel, une carte mémoire). Un signalement est pertinent, par exemple, si :

- une image ou un fichier RAW fait planter le moteur ou l'interface d'une façon exploitable, fait exécuter du code, ou fait lire ou écrire des fichiers en dehors du dossier de destination choisi ;
- un nom de fichier ou de dossier fait exécuter une commande à l'extension Nautilus ou à l'interface ;
- le paquet `.deb` ou `.rpm`, son script d'installation ou les scripts de publication peuvent être détournés ;
- un fichier d'une version publiée ne correspond pas à son empreinte `.sha256` publiée.

## Ce qui n'est pas concerné

- Une vulnérabilité dans **Nautilus, nautilus-python, GTK ou le système** lui-même : merci de la signaler au projet ou à la distribution concernés.
- Une vulnérabilité dans un **composant développé par quelqu'un d'autre** : merci de la signaler à ce projet. Certains de ces composants sont **intégrés au programme** (les décodeurs d'images et de RAW en Rust comme `rawloader`, et LibRaw, compilée statiquement) : les utilisateurs ne peuvent pas les mettre à jour séparément, alors prévenez-moi aussi, puisque le correctif demande une nouvelle version de nautilus-convert-images.
- Les problèmes qui supposent un ordinateur déjà compromis, ou un accès physique à celui-ci.
- Les bugs ordinaires sans conséquence pour la sécurité : ouvrez plutôt une [issue](https://github.com/gillesmagneville/nautilus-convert-images/issues).

## Vérifier ce que vous téléchargez

Téléchargez les paquets uniquement depuis la page des [Releases](https://github.com/gillesmagneville/nautilus-convert-images/releases) de ce dépôt. Chaque paquet est publié avec son propre fichier `.sha256` (il n'y a pas de `SHA256SUMS` global). Pour vérifier un téléchargement, placez le paquet et son fichier `.sha256` dans le même dossier :

```bash
sha256sum -c nautilus-convert-images_X.Y.Z_amd64.deb.sha256
```
