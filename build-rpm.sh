#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

# ============================================================
# nautilus-convert-images - build-rpm.sh
#
# Construit un paquet .rpm (Fedora, RHEL, Rocky, AlmaLinux, openSUSE, ...)
# avec fpm. Meme structure et memes principes que build-deb.sh : voir ce
# fichier pour les commentaires detailles sur chaque etape.
# ============================================================

PACKAGE_NAME="nautilus-convert-images"
MAINTAINER="Your Name <you@example.com>"   # <-- a personnaliser
DESCRIPTION="Conversion d'images (RAW, JPEG, PNG, TIFF, BMP, WebP) sans perte, integree au menu contextuel de Nautilus"
URL="https://github.com/gillesmagneville/nautilus-convert-images"   # <-- a verifier

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$HOME/nautilus-convert-images-build/rpm"
VERSION_FILE="$PROJECT_DIR/VERSION"
CARGO_TOML="$PROJECT_DIR/Cargo.toml"

show_help() {
  cat <<EOF
Usage: ./build-rpm.sh [options]

Construit un paquet .rpm pour nautilus-convert-images.

  --major               Incremente le numero majeur (1.2.3 -> 2.0.0)
  --minor               Incremente le numero mineur (1.2.3 -> 1.3.0)
  --patch               Incremente le numero de patch (1.2.3 -> 1.2.4)
  --no-version-change   Reconstruit sans changer la version
  --yes, -y             Ne pas demander de confirmation avant de construire
  --clean               Nettoie le dossier de build et les .rpm generes
  --help, -h            Affiche cette aide

Sans argument de version : mode interactif (necessite un terminal).
EOF
}

INCREMENT=""
NO_VERSION_CHANGE=false
ASSUME_YES=false
CLEAN=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --major) INCREMENT="major"; shift ;;
    --minor) INCREMENT="minor"; shift ;;
    --patch) INCREMENT="patch"; shift ;;
    --no-version-change) NO_VERSION_CHANGE=true; shift ;;
    --yes|-y) ASSUME_YES=true; shift ;;
    --clean) CLEAN=true; shift ;;
    --help|-h) show_help; exit 0 ;;
    *) echo "Option inconnue : $1"; show_help; exit 1 ;;
  esac
done

if [ "$CLEAN" = true ]; then
  echo ">>> Nettoyage du dossier de build et des .rpm generes..."
  rm -rf "$BUILD_DIR"
  rm -f "$PROJECT_DIR"/*.rpm
  echo ">>> Termine."
  exit 0
fi

# --- Verification des outils requis ---
if ! command -v fpm &> /dev/null; then
  echo "Erreur : fpm n'est pas installe."
  echo "Installe-le avec : gem install --user-install fpm"
  exit 1
fi
if ! command -v cargo &> /dev/null; then
  echo "Erreur : cargo (Rust) n'est pas installe. Voir https://rustup.rs"
  exit 1
fi
if ! command -v rpmbuild &> /dev/null; then
  echo "Erreur : rpmbuild introuvable (necessaire pour generer un .rpm)."
  echo "Sur Debian/Ubuntu :               sudo apt install rpm"
  echo "Sur Fedora/RHEL/Rocky/AlmaLinux : sudo dnf install rpm-build"
  echo "Sur openSUSE :                    sudo zypper install rpm-build"
  exit 1
fi

# --- Lecture de la version actuelle ---
CURRENT_VERSION="0.1.0"
[ -f "$VERSION_FILE" ] && CURRENT_VERSION=$(tr -d '[:space:]' < "$VERSION_FILE")

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
MAJOR=${MAJOR:-0}; MINOR=${MINOR:-0}; PATCH=${PATCH:-0}

# --- Mode interactif si aucun argument de version fourni ---
# Sans flag de version ET sans terminal interactif, il n'y a aucune
# facon de savoir quoi faire : mieux vaut echouer clairement ici que de
# laisser `read` toucher un EOF silencieux plus loin (ce qui, avec
# `set -e`, tuerait le script sans message avant meme la compilation --
# VERSION et Cargo.toml resteraient donc inchanges sans aucune explication).
if [ -z "$INCREMENT" ] && [ "$NO_VERSION_CHANGE" = false ]; then
  if [ ! -t 0 ]; then
    echo "Erreur : aucun flag de version fourni (--major/--minor/--patch/"
    echo "--no-version-change) et aucun terminal interactif disponible pour"
    echo "le menu de choix. Relance avec l'un de ces flags."
    exit 1
  fi
  echo ""
  echo "Version actuelle : $CURRENT_VERSION"
  echo ""
  echo "  1) major (-> $((MAJOR + 1)).0.0)"
  echo "  2) minor (-> $MAJOR.$((MINOR + 1)).0)"
  echo "  3) patch (-> $MAJOR.$MINOR.$((PATCH + 1)))"
  echo "  4) no-version-change (reconstruire en $CURRENT_VERSION)"
  echo ""
  read -p "Choix [1/2/3/4] : " CHOICE
  case $CHOICE in
    1) INCREMENT="major" ;;
    2) INCREMENT="minor" ;;
    3) INCREMENT="patch" ;;
    4) NO_VERSION_CHANGE=true ;;
    *) echo "Choix invalide. Annulation."; exit 1 ;;
  esac
fi

if [ "$NO_VERSION_CHANGE" = true ]; then
  NEW_VERSION="$CURRENT_VERSION"
else
  case $INCREMENT in
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch) PATCH=$((PATCH + 1)) ;;
  esac
  NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
fi

echo ""
echo "========================================"
echo " Paquet   : $PACKAGE_NAME"
echo " Version  : $CURRENT_VERSION -> $NEW_VERSION"
echo " Format   : .rpm"
echo "========================================"
echo ""
# A ce stade, soit un flag de version a ete fourni explicitement (dans
# ce cas stdin peut etre non-interactif : c'est un usage scripte/CI
# legitime), soit le menu interactif ci-dessus a deja confirme qu'un
# terminal est bien disponible. Ne demander confirmation que si on peut
# reellement lire une reponse -- sinon `read` echoue silencieusement sur
# EOF et, avec `set -e`, tuerait le script sans message avant meme de
# compiler.
if [ "$ASSUME_YES" = true ]; then
  echo "Confirmation automatique (--yes)."
elif [ -t 0 ]; then
  read -p "Construire ? [o/N] " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[oOyY]$ ]]; then
    echo "Construction annulee. Aucun fichier n'a ete modifie."
    exit 0
  fi
else
  echo "Pas de terminal interactif : confirmation automatique (un flag de version a ete fourni explicitement)."
fi

# --- Mise a jour temporaire de Cargo.toml AVANT compilation, pour que le
#     binaire embarque le bon numero via `convert-images-engine --version`.
#     Reverti si une etape echoue plus loin. ---
if [ "$NEW_VERSION" != "$CURRENT_VERSION" ]; then
  sed -i "s/^version = \".*\"/version = \"$NEW_VERSION\"/" "$CARGO_TOML"
fi

echo ""
echo ">>> Compilation en mode release (cargo build --release)..."
BUILD_LOG=$(mktemp)
if (cd "$PROJECT_DIR" && cargo build --release --quiet) > "$BUILD_LOG" 2>&1; then
  rm -f "$BUILD_LOG"
  echo ">>> Compilation reussie."
else
  echo ""
  echo "Erreur : la compilation a echoue."
  echo ""
  sed 's/^/  /' "$BUILD_LOG"
  rm -f "$BUILD_LOG"
  sed -i "s/^version = \".*\"/version = \"$CURRENT_VERSION\"/" "$CARGO_TOML"
  echo ""
  echo "Construction annulee : Cargo.toml restaure, aucun paquet genere."
  exit 1
fi

ENGINE_BINARY="$PROJECT_DIR/target/release/convert-images-engine"
if [ ! -f "$ENGINE_BINARY" ]; then
  echo "Erreur : binaire du moteur introuvable apres compilation ($ENGINE_BINARY)."
  sed -i "s/^version = \".*\"/version = \"$CURRENT_VERSION\"/" "$CARGO_TOML"
  exit 1
fi

# --- Staging ---
echo ">>> Creation de l'arborescence de staging..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/usr/bin"
mkdir -p "$BUILD_DIR/usr/share/nautilus-python/extensions"
mkdir -p "$BUILD_DIR/usr/share/applications"
mkdir -p "$BUILD_DIR/usr/share/doc/$PACKAGE_NAME"

cp "$ENGINE_BINARY" "$BUILD_DIR/usr/bin/convert-images-engine"
cp "$PROJECT_DIR/nautilus-extension/convert-images-gui" "$BUILD_DIR/usr/bin/convert-images-gui"
cp "$PROJECT_DIR/nautilus-extension/convert_images_nautilus.py" \
  "$BUILD_DIR/usr/share/nautilus-python/extensions/convert_images_nautilus.py"
cp "$PROJECT_DIR/packaging/nautilus-convert-images.desktop" \
  "$BUILD_DIR/usr/share/applications/nautilus-convert-images.desktop"
for doc in README.md CHANGELOG.md PROJECT_CONTEXT.md ARCHITECTURE.md CONTRIBUTING.md LICENSE; do
  [ -f "$PROJECT_DIR/$doc" ] && cp "$PROJECT_DIR/$doc" "$BUILD_DIR/usr/share/doc/$PACKAGE_NAME/"
done

# Normalisation des permissions : cp applique l'umask courant de la
# machine de build, pas les permissions de la source. On force donc des
# permissions coherentes, comme dans build-deb.sh de linuxdoctor.
echo ">>> Normalisation des permissions..."
find "$BUILD_DIR" -type d -exec chmod 755 {} +
find "$BUILD_DIR" -type f -exec chmod 644 {} +
chmod +x "$BUILD_DIR/usr/bin/convert-images-engine"
chmod +x "$BUILD_DIR/usr/bin/convert-images-gui"

# --- Construction du paquet ---
echo ""
echo ">>> Construction du paquet .rpm (fpm)..."
rm -f "$PROJECT_DIR"/*.rpm

if (cd "$PROJECT_DIR" && fpm -s dir -t rpm \
  -n "$PACKAGE_NAME" \
  -v "$NEW_VERSION" \
  --license "GPL-3.0-only" \
  --maintainer "$MAINTAINER" \
  --description "$DESCRIPTION" \
  --url "$URL" \
  --depends "python3-gi" \
  --depends "gir1.2-gtk-4.0" \
  --depends "python3-nautilus" \
  --after-install "$PROJECT_DIR/packaging/postinst" \
  -C "$BUILD_DIR" \
  usr/); then

  # --- Version enregistree seulement apres un build complet reussi ---
  echo "$NEW_VERSION" > "$VERSION_FILE"
  echo ""
  echo "Paquet genere :"
  ls -1 "$PROJECT_DIR"/*.rpm | sed 's/^/   /'
  echo "Version enregistree : $NEW_VERSION (VERSION + Cargo.toml)"
  echo ""
  echo "Note : le nom du fichier .rpm contient un '-1' apres le numero de"
  echo "version (ex. ${PACKAGE_NAME}-${NEW_VERSION}-1.x86_64.rpm). C'est le"
  echo "champ \"Release\" du format RPM (distinct de \"Version\" dans la"
  echo "convention NEVRA : Nom-Epoch:Version-Release.Architecture), fixe a 1"
  echo "par defaut par fpm. Ce n'est pas une modification du numero de"
  echo "version -- VERSION et Cargo.toml ci-dessus restent exacts, sans"
  echo "aucun suffixe. Le format .deb n'a pas cette notion, d'ou l'absence"
  echo "de ce suffixe cote build-deb.sh."
else
  echo ""
  echo "Erreur : fpm a echoue."
  sed -i "s/^version = \".*\"/version = \"$CURRENT_VERSION\"/" "$CARGO_TOML"
  rm -rf "$BUILD_DIR"
  echo "Construction annulee : Cargo.toml restaure."
  exit 1
fi
