<!-- SPDX-License-Identifier: GPL-3.0-only -->

# PROJECT_CONTEXT.fr.md

🇬🇧 [English version](PROJECT_CONTEXT.md)

# nautilus-convert-images

**nautilus-convert-images** est une extension open-source pour Nautilus (GNOME
Fichiers) qui convertit des images — y compris les fichiers RAW d'appareil
photo — entre formats courants, directement depuis le menu contextuel.

Son objectif est de rendre la conversion d'images aussi simple qu'un clic
droit, sans jamais sacrifier la qualité de l'image ni obliger l'utilisateur à
ouvrir un terminal ou un logiciel de retouche.

nautilus-convert-images s'adresse à :

* les photographes amateurs et semi-professionnels
* les utilisateurs de bureau Linux/GNOME en général
* les personnes qui reçoivent des fichiers RAW ou TIFF et ont juste besoin
  d'un JPEG (ou l'inverse) sans rien connaître à la photo
* les administrateurs qui préparent des postes de travail

Il est conçu pour fonctionner **entièrement en local**, sans compte, sans
service en ligne, sans télémétrie.

> **Note sur ce document :** PROJECT_CONTEXT.fr.md définit *pourquoi* le projet
> existe et *ce qu'il valorise*. Il ne redéfinit pas les formats de données
> exacts (schéma JSON du moteur, énumérations, contrat du CLI) — ceux-ci
> vivent une seule fois, de façon canonique, dans `ARCHITECTURE.fr.md`, pour que
> les deux documents ne puissent pas silencieusement diverger.

---

# Vision

La plupart des outils de conversion d'image sur Linux demandent soit une
ligne de commande (`convert`, `dcraw`, `exiftool`...), soit un logiciel de
retouche complet (darktable, GIMP) pour une tâche qui devrait être triviale.

nautilus-convert-images vise à répondre à une question simple :

> **« J'ai sélectionné des photos dans mon gestionnaire de fichiers, je veux
> les avoir dans un autre format, sans rien perdre — comment ? »**

Plutôt que de remplacer les outils de traitement RAW avancés comme
darktable, RawTherapee ou GIMP, nautilus-convert-images s'occupe uniquement
de la conversion de format brute, sans retouche, exactement comme le ferait
l'appareil photo lui-même en exportant un JPEG depuis son propre écran.

---

# Philosophie du projet

nautilus-convert-images suit cinq principes.

## 1. Ne jamais perdre plus que le format ne l'impose

PNG, TIFF, BMP et WebP (mode sans perte) sont réencodés sans aucune perte
d'information — vérifié pixel à pixel. JPEG reste par nature un format avec
perte : ce n'est pas contournable, et l'outil ne prétend jamais le
contraire. La qualité par défaut (100) minimise cette perte autant que le
format le permet.

## 2. Ne jamais recadrer, ne jamais redimensionner

Aucune étape du pipeline ne rogne ni ne réduit la résolution d'une image, à
moins que l'utilisateur ne le demande explicitement — ce qu'aucune version
actuelle de l'outil ne propose. Une image RAW est décodée à la résolution
exacte de la zone active du capteur, identique à ce que produirait
l'appareil photo.

## 3. Lecture seule sur les fichiers source

nautilus-convert-images ne modifie et ne supprime jamais le fichier
d'origine. Il :

* lit
* convertit
* écrit un nouveau fichier ailleurs (ou sous un nouveau nom)

Il ne modifie jamais un fichier en place.

## 4. S'intégrer au flux de travail existant, pas en créer un nouveau

Pas de nouvelle application à apprendre : le point d'entrée est le menu
contextuel de Nautilus que l'utilisateur connaît déjà. L'interface
graphique ne s'ouvre qu'à la demande, pour cette seule tâche.

## 5. Rapide

Le décodage et l'encodage utilisent du code natif (Rust, avec LibRaw en C++
en secours pour les RAW) et exploitent tous
les cœurs disponibles pour les conversions par lot. Aucune conversion ne
doit sembler plus lente que d'ouvrir l'image dans une visionneuse.

---

# Périmètre du projet

nautilus-convert-images se concentre sur :

* la détection de format d'image (standard et RAW)
* la conversion de format, sans retouche
* l'intégration au menu contextuel de Nautilus
* la gestion du dossier de destination (y compris la création d'un nouveau
  dossier) et des collisions de noms

nautilus-convert-images n'est **pas** :

* un éditeur RAW (pas de réglage d'exposition, de balance des blancs
  manuelle, de courbes, de recadrage)
* un remplaçant de darktable, RawTherapee ou GIMP
* un outil de renommage ou d'organisation de photothèque
* un service de conversion en ligne ou un démon en arrière-plan

---

# Plateformes cibles

Cible principale : bureau Linux avec Nautilus (GNOME Fichiers) 4.x / GTK4.

Distributions visées :

* Debian
* Ubuntu
* Fedora
* openSUSE
* toute distribution basée sur GNOME avec `nautilus-python` disponible

Architecture : x86_64 en priorité ; ARM64 dans la mesure où les dépendances
Rust utilisées s'y compilent sans adaptation particulière. LibRaw (C++,
embarquée dans `vendor/` et compilée avec `g++`, utilisée en secours) devrait
aussi s'y compiler, mais cela n'a pas été vérifié.

---

# Expérience utilisateur

Utiliser nautilus-convert-images doit rester simple :

1. Sélectionner des fichiers et/ou dossiers dans Nautilus.
2. Clic droit → **Convertir les images…** (« Convert images… » en anglais,
   « Convertir imágenes… » en espagnol, « Bilder konvertieren … » en allemand :
   la langue suit celle de la session)
3. Choisir le format de destination et le dossier de sortie.
4. Convertir.

Aucune étape de configuration préalable, aucun compte, aucune connexion
réseau requise.

---

# Formats

**Formats source détectés** : JPEG, PNG, TIFF, BMP, GIF, WebP, et une large
gamme de formats RAW d'appareil photo (Canon, Nikon, Sony, Adobe DNG,
Olympus, Fujifilm, Panasonic, Pentax, Samsung, Sigma, Hasselblad, Leica,
GoPro...). La liste exacte des formats de destination et leurs garanties
(sans perte ou non) sont définies une seule fois dans `ARCHITECTURE.fr.md`.

---

# Fiabilité et transparence

nautilus-convert-images ne prétend jamais qu'une conversion est sans perte
quand elle ne l'est pas (cas du JPEG). Quand une limite existe, elle est
documentée et affichée, pas cachée.

---

# Extensibilité

Ajouter un nouveau format de destination ou source ne doit toucher qu'un
petit nombre de points bien identifiés du moteur, sans affecter l'extension
Nautilus ni l'interface graphique. Le contrat exact (où ajouter quoi) est
défini dans `ARCHITECTURE.fr.md`.

---

# Objectifs de performance

* Détection : quasi instantanée, même sur plusieurs milliers de fichiers
* Conversion : parallélisée sur tous les cœurs disponibles
* Aucun processus résident en arrière-plan une fois la conversion terminée
* Aucune télémétrie, aucune dépendance à un service en ligne

---

# Principes de code

* Rust stable uniquement — pas de fonctionnalités nightly
* Rust sûr (`unsafe` évité) pour le moteur
* Python + PyGObject pour l'intégration Nautilus et l'interface graphique,
  qui n'ont pas besoin d'être du code natif compilé
* Une dépendance n'est ajoutée que si elle apporte un bénéfice net clair —
  voir « Philosophie des dépendances » dans `ARCHITECTURE.fr.md`

---

# Vision future

Des versions futures pourraient inclure :

* prise en charge de HEIF/AVIF en sortie
* renommage par motif lors de la conversion par lot
* profil de couleur explicite en sortie (au-delà du sRGB par défaut)
* langues d'interface supplémentaires (l'interface existe déjà en anglais,
  français, espagnol et allemand : voir `CONTRIBUTING.fr.md`)

Aucun de ces points n'est requis pour que l'outil soit utile. La v1 reste
volontairement ciblée : détection, conversion sans perte, intégration
Nautilus.

---

# Non-objectifs

nautilus-convert-images ne cherchera jamais à devenir :

* un éditeur RAW complet
* un gestionnaire de photothèque
* un outil de traitement par lot généraliste (redimensionnement,
  filigrane, filtres...)

Il doit rester un outil de conversion de format, focalisé et prévisible.

---

# Valeurs du projet

nautilus-convert-images valorise :

* la fidélité au fichier source
* la clarté (dire quand un format est intrinsèquement limité, plutôt que
  de le cacher)
* la rapidité
* la simplicité d'intégration (un menu contextuel, pas une nouvelle
  application à apprendre)
* la transparence sur le fonctionnement et les limites de l'outil

Avant tout :

**Une conversion ne doit jamais surprendre l'utilisateur — ni par une
perte de qualité non annoncée, ni par un recadrage, ni par une résolution
réduite.**
