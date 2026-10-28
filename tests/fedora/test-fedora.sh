#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Teste un paquet .rpm dans un vrai Fedora (conteneur), depuis votre machine :
# installation avec dnf (dépendances résolues par Fedora), contenu du paquet,
# moteur, GTK 4, extension Nautilus avec les vraies liaisons nautilus-python,
# interface complète sous Xvfb dans les 4 langues, puis désinstallation.
#
#   tests/fedora/test-fedora.sh [fichier.rpm] [version-de-Fedora]
#
# Sans fichier .rpm, le script prend celui de la racine du dépôt (il doit n'y
# en avoir qu'un). La version de Fedora est « latest » par défaut ; exemples :
# 43, 44. Il faut podman (de préférence) ou docker : sudo apt install podman
#
# À lancer AVANT de publier une release, sur le .rpm qui va être publié.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$TESTS_DIR")"

RPM="${1:-}"
VERSION="${2:-latest}"

if [ -z "$RPM" ]; then
    shopt -s nullglob
    found=("$ROOT_DIR"/*.rpm)
    shopt -u nullglob
    if [ "${#found[@]}" -eq 1 ]; then
        RPM="${found[0]}"
    else
        echo "Usage : $0 [fichier.rpm] [version-de-Fedora]" >&2
        echo "${#found[@]} fichier(s) .rpm à la racine du dépôt : précisez lequel en argument." >&2
        exit 2
    fi
fi

if [ ! -f "$RPM" ]; then
    echo "Fichier introuvable : '${RPM}'" >&2
    exit 2
fi

RUNTIME="$(command -v podman || command -v docker || true)"
if [ -z "$RUNTIME" ]; then
    echo "Ni podman ni docker n'est installé. Installez podman avec :" >&2
    echo "    sudo apt install podman" >&2
    exit 2
fi

RPM_DIR="$(cd "$(dirname "$RPM")" && pwd)"
RPM_NAME="$(basename "$RPM")"
IMAGE="registry.fedoraproject.org/fedora:${VERSION}"

echo "Moteur de conteneurs : $RUNTIME"
echo "Image                : $IMAGE (téléchargée la première fois, environ 60 Mo)"
echo "Paquet               : $RPM_DIR/$RPM_NAME"
echo "Le dossier du paquet et le dossier tests/ sont montés en LECTURE SEULE dans le conteneur ;"
echo "le conteneur est supprimé à la fin. Rien n'est installé sur votre machine."
echo

"$RUNTIME" run --rm \
    -v "$RPM_DIR":/pkg:ro \
    -v "$TESTS_DIR":/tests:ro \
    -e RPM_NAME="$RPM_NAME" \
    "$IMAGE" bash /tests/fedora/inside-fedora.sh
