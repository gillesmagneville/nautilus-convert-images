#!/usr/bin/env bash
# Construit les paquets .deb et .rpm de nautilus-convert-images avec fpm.
#
# Prérequis sur la machine de build :
#   - Rust (cargo/rustc) pour compiler le moteur
#   - fpm (gem install fpm) — voir https://fpm.readthedocs.io/
#   - dpkg-deb (paquets .deb) et rpmbuild (paquets .rpm)
#
# Important : tous les fichiers sont installés sous /usr (jamais
# /usr/local), car le bac à sable bwrap de Nautilus ne monte pas
# /usr/local — un binaire installé là serait invisible depuis
# l'extension (leçon apprise sur raw-thumbs).

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(cat VERSION)"
ARCH="amd64"
RPM_ARCH="x86_64"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> Compilation du moteur (release)"
cargo build --release

echo "==> Préparation de l'arborescence de staging ($STAGE)"
install -Dm755 target/release/convert-images-engine "$STAGE/usr/bin/convert-images-engine"
install -Dm755 nautilus-extension/convert-images-gui "$STAGE/usr/bin/convert-images-gui"
install -Dm644 nautilus-extension/convert_images_nautilus.py \
    "$STAGE/usr/share/nautilus-python/extensions/convert_images_nautilus.py"
install -Dm644 packaging/nautilus-convert-images.desktop \
    "$STAGE/usr/share/applications/nautilus-convert-images.desktop"
install -Dm644 README.md "$STAGE/usr/share/doc/nautilus-convert-images/README.md"
install -Dm644 CHANGELOG.md "$STAGE/usr/share/doc/nautilus-convert-images/CHANGELOG.md"
install -Dm644 LICENSE "$STAGE/usr/share/doc/nautilus-convert-images/LICENSE"

COMMON_FPM_ARGS=(
    -s dir
    -C "$STAGE"
    -n nautilus-convert-images
    -v "$VERSION"
    --description "Conversion d'images (RAW, JPEG, PNG, TIFF, BMP, WebP) sans perte, integree au menu contextuel de Nautilus"
    --url "https://github.com/gillesmagneville/nautilus-convert-images"
    --license "GPL-3.0-only"
    --maintainer "Gilles Magneville"
    --after-install packaging/postinst
    usr
)

mkdir -p dist

echo "==> Paquet .deb"
fpm -t deb \
    -p "dist/nautilus-convert-images_${VERSION}_${ARCH}.deb" \
    --depends "python3-gi" \
    --depends "gir1.2-gtk-4.0" \
    --depends "python3-nautilus" \
    "${COMMON_FPM_ARGS[@]}"

echo "==> Paquet .rpm"
fpm -t rpm \
    -p "dist/nautilus-convert-images-${VERSION}.${RPM_ARCH}.rpm" \
    --depends "python3-gobject" \
    --depends "gtk4" \
    --depends "nautilus-python" \
    "${COMMON_FPM_ARGS[@]}"

echo "==> Terminé : dist/"
ls -la dist/
