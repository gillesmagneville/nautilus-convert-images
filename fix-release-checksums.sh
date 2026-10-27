#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

# ============================================================
# fix-release-checksums.sh
#
# Remplace, sur une release GitHub DEJA publiee, le fichier unique
# SHA256SUMS par un fichier .sha256 par paquet, et corrige les notes
# de release en consequence. Les empreintes sont relues depuis la
# release elle-meme (donc celles des paquets reellement publies) et
# controlees sur les paquets re-telecharges avant toute modification.
#
# Usage : ./fix-release-checksums.sh [--yes] [vX.Y.Z]     (defaut : v1.1.0)
# ============================================================

REPO="gillesmagneville/nautilus-convert-images"
PKG="nautilus-convert-images"
ASSUME_YES=false
TAG="v1.1.0"

for arg in "$@"; do
  case "$arg" in
    --yes|-y) ASSUME_YES=true ;;
    v[0-9]*) TAG="$arg" ;;
    *) echo "Usage : $0 [--yes] [vX.Y.Z]" >&2; exit 1 ;;
  esac
done

die() { printf '\nErreur : %s\n' "$*" >&2; exit 1; }

command -v gh >/dev/null 2>&1 || die "gh est introuvable."
command -v python3 >/dev/null 2>&1 || die "python3 est introuvable."
command -v sha256sum >/dev/null 2>&1 || die "sha256sum est introuvable."

VERSION="${TAG#v}"
DEB="${PKG}_${VERSION}_amd64.deb"
RPM="${PKG}-${VERSION}-1.x86_64.rpm"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

echo ">>> Etat actuel de la release $TAG"
ASSETS="$(gh release view "$TAG" --repo "$REPO" --json assets --jq '.assets[].name')" \
  || die "release $TAG introuvable sur $REPO."
printf '%s\n' "$ASSETS" | sed 's/^/    /'

for a in "$DEB" "$RPM"; do
  printf '%s\n' "$ASSETS" | grep -qxF "$a" || die "paquet absent de la release : $a"
done

if ! printf '%s\n' "$ASSETS" | grep -qxF SHA256SUMS; then
  if printf '%s\n' "$ASSETS" | grep -qxF "$DEB.sha256" && printf '%s\n' "$ASSETS" | grep -qxF "$RPM.sha256"; then
    echo "Rien a faire : la release a deja un fichier .sha256 par paquet."
    exit 0
  fi
  die "SHA256SUMS est absent mais les .sha256 par paquet aussi : etat inattendu."
fi

echo ""
echo ">>> Lecture des empreintes publiees (SHA256SUMS)"
gh release download "$TAG" --repo "$REPO" --pattern SHA256SUMS
for f in "$DEB" "$RPM"; do
  line="$(grep -E "[[:space:]]\*?${f//./\\.}\$" SHA256SUMS || true)"
  [ -n "$line" ] || die "pas d'empreinte pour $f dans SHA256SUMS."
  hash="${line%%[[:space:]]*}"
  [[ "$hash" =~ ^[0-9a-f]{64}$ ]] || die "empreinte invalide pour $f."
  printf '%s  %s\n' "$hash" "$f" > "$f.sha256"
  echo "    $f.sha256 : $hash"
done

echo ""
echo ">>> Controle sur les paquets re-telecharges depuis la release"
gh release download "$TAG" --repo "$REPO" --pattern "$DEB" --pattern "$RPM"
sha256sum -c "$DEB.sha256" "$RPM.sha256" || die "les paquets publies ne correspondent pas aux empreintes : rien n'a ete modifie."

echo ""
echo ">>> Mise a jour des notes de release"
gh release view "$TAG" --repo "$REPO" --json body --jq .body > notes.md
python3 -I - "$VERSION" notes.md <<'PY'
import re, sys

version, path = sys.argv[1], sys.argv[2]
body = open(path, encoding="utf-8", newline="").read()
deb = f"nautilus-convert-images_{version}_amd64.deb"
rpm = f"nautilus-convert-images-{version}-1.x86_64.rpm"
old = re.compile(r"Vérification des téléchargements : `sha256sum -c SHA256SUMS`\.")
nl = "\r\n" if "\r\n" in body else "\n"
new = ("Vérification des téléchargements (le paquet et son fichier `.sha256` dans le même dossier) :"
       + nl + nl + "```bash" + nl + f"sha256sum -c {deb}.sha256" + nl
       + f"sha256sum -c {rpm}.sha256" + nl + "```")
out, n = old.subn(lambda m: new, body)
if n != 1:
    sys.exit("ligne SHA256SUMS introuvable dans les notes : rien n'a ete modifie.")
open(path, "w", encoding="utf-8", newline="").write(out)
PY
echo "    notes pretes (modifiees en local, pas encore envoyees)."

echo ""
echo "Actions prevues sur $TAG ($REPO) :"
echo "    + ajouter $DEB.sha256 et $RPM.sha256"
echo "    ~ remplacer le texte de verification dans les notes"
echo "    - supprimer SHA256SUMS"
if ! $ASSUME_YES; then
  [ -t 0 ] || die "pas de terminal interactif : relancez avec --yes."
  read -r -p $'\nAppliquer ? [o/N] ' a
  [[ "$a" =~ ^[oOyY]$ ]] || { echo "Annule. La release n'a pas ete modifiee."; exit 0; }
fi

# Ordre voulu : on ajoute d'abord, on supprime l'ancien fichier en dernier,
# pour qu'il n'y ait jamais un moment sans empreintes disponibles.
gh release upload "$TAG" --repo "$REPO" --clobber "$DEB.sha256" "$RPM.sha256"
gh release edit "$TAG" --repo "$REPO" --notes-file notes.md
gh release delete-asset "$TAG" --repo "$REPO" SHA256SUMS --yes

echo ""
echo ">>> Verification finale"
FINAL="$(gh release view "$TAG" --repo "$REPO" --json assets --jq '.assets[].name')"
printf '%s\n' "$FINAL" | sed 's/^/    /'
for a in "$DEB" "$RPM" "$DEB.sha256" "$RPM.sha256"; do
  printf '%s\n' "$FINAL" | grep -qxF "$a" || die "fichier absent de la release : $a"
done
if printf '%s\n' "$FINAL" | grep -qxF SHA256SUMS; then
  die "SHA256SUMS est toujours present."
fi
echo ""
echo "Release $TAG corrigee : un fichier .sha256 par paquet."
