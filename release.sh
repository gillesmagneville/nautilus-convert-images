#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

# ============================================================
# nautilus-convert-images - release.sh
#
# Publie la release stable GitHub correspondant au contenu de VERSION :
#   1. controles prealables (branche, remote, tag libre, correctifs presents)
#   2. mise en coherence (MAINTAINER, dependances .rpm, Cargo.toml, README,
#      CHANGELOG) puis reconstruction des paquets si necessaire
#   3. verification du contenu des paquets (.deb / .rpm)
#   4. commit + push sur main
#   5. creation de la release (tag, notes, .deb, .rpm, un .sha256 par paquet)
#
# Les notes de la release sont publiees en anglais d'abord (le README affiche
# l'anglais par defaut), puis en francais. Elles viennent de la section datee
# du jour de CHANGELOG.md (anglais) et de CHANGELOG.fr.md (francais) : les deux
# sont obligatoires.
#
# A lancer depuis la racine du depot, apres les builds habituels.
# Utiliser --dry-run pour tout voir sans rien modifier ni publier.
# ============================================================

REPO_SLUG="gillesmagneville/nautilus-convert-images"
PKG="nautilus-convert-images"
DRY_RUN=false
ASSUME_YES=false

show_help() {
  cat <<EOF
Usage: ./release.sh [options]

Publie la release stable GitHub de nautilus-convert-images (tag v\$(cat VERSION)).

  --dry-run    Affiche ce qui serait fait (et les notes de release) sans rien
               modifier, committer, pousser ni publier
  --yes, -y    Ne pas demander de confirmation (variables utiles :
               RAW_TESTED=1 si un vrai fichier RAW a ete converti avec succes,
               RELEASE_MAINTAINER="Nom <email>" pour le champ maintainer)
  --help, -h   Affiche cette aide
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --yes|-y) ASSUME_YES=true; shift ;;
    --help|-h) show_help; exit 0 ;;
    *) echo "Option inconnue : $1" >&2; show_help >&2; exit 1 ;;
  esac
done

step() { printf '\n>>> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
die()  { printf '\nErreur : %s\n' "$*" >&2; exit 1; }

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ------------------------------------------------------------
# 1. Controles prealables
# ------------------------------------------------------------
step "Controles prealables"

for t in git gh python3 sha256sum dpkg-deb tar; do
  command -v "$t" >/dev/null 2>&1 || die "outil manquant : $t"
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "ce dossier n'est pas un depot git."
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || die "la branche courante n'est pas 'main'."

ORIGIN_URL="$(git remote get-url origin 2>/dev/null)" || die "pas de remote 'origin'."
case "$ORIGIN_URL" in
  *"$REPO_SLUG"*) ;;
  *) die "origin ne pointe pas vers $REPO_SLUG ($ORIGIN_URL)." ;;
esac

if ! gh auth status >/dev/null 2>&1; then
  if $DRY_RUN; then
    warn "gh n'est pas authentifie (lancez 'gh auth login' avant la vraie publication)."
  else
    die "gh n'est pas authentifie : lancez 'gh auth login'."
  fi
fi

git fetch --quiet --tags origin || die "git fetch origin a echoue."
if git rev-parse -q --verify origin/main >/dev/null; then
  BEHIND="$(git rev-list --count HEAD..origin/main)"
  [ "$BEHIND" = "0" ] || die "origin/main contient $BEHIND commit(s) absent(s) en local : faites d'abord 'git pull --rebase'."
fi

[ -f VERSION ] || die "fichier VERSION introuvable."
VERSION="$(tr -d '[:space:]' < VERSION)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "VERSION invalide : '$VERSION' (attendu X.Y.Z)."
TAG="v$VERSION"
PREV_TAG="$(git tag -l 'v[0-9]*' --sort=-v:refname | grep -vxF "$TAG" | head -1 || true)"
if [ -n "$PREV_TAG" ]; then
  FIRST_RELEASE=false
  [ "$(printf '%s\n%s\n' "${PREV_TAG#v}" "$VERSION" | sort -V | tail -1)" = "$VERSION" ] \
    || die "VERSION ($VERSION) n'est pas superieure a la derniere release ($PREV_TAG)."
  info "Version : $VERSION  ->  tag $TAG  (derniere release : $PREV_TAG)"
else
  FIRST_RELEASE=true
  info "Version : $VERSION  ->  tag $TAG  (premiere release)"
fi
export FIRST_RELEASE

# Si VERSION est deja publiee, il suffit presque toujours d'avoir oublie de
# passer a la version suivante : on dit quoi faire (VERSION n'avance que par
# un build reussi, voir CHANGELOG.md).
NEXT_HINT="VERSION ($VERSION) est deja publiee. Pour passer a la version suivante, lancez d'abord :
    ./build-deb.sh --patch --yes     (ou --minor / --major a la place de --patch)
    ./build-rpm.sh --no-version-change --yes
  puis relancez ./release.sh."
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  die "le tag $TAG existe deja en local.
  $NEXT_HINT"
fi
if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
  die "le tag $TAG existe deja sur GitHub.
  $NEXT_HINT"
fi
if gh release view "$TAG" --repo "$REPO_SLUG" >/dev/null 2>&1; then
  die "une release $TAG existe deja sur GitHub.
  $NEXT_HINT"
fi

# Vrai si le fichier fige la version de Nautilus par une instruction ACTIVE
# (les lignes de commentaire qui citent l'instruction ne comptent pas).
has_nautilus_pin() {
  grep -Eq '^[[:space:]]*gi\.require_version\([[:space:]]*["'"'"']Nautilus["'"'"']' "$1"
}

EXT="nautilus-extension/convert_images_nautilus.py"
GUI="nautilus-extension/convert-images-gui"
[ -f "$EXT" ] && [ -f "$GUI" ] || die "extension ou IHM introuvable dans nautilus-extension/."
if has_nautilus_pin "$EXT"; then
  die "$EXT fige encore la version de Nautilus (correctif Nautilus 4.1 absent)."
fi
grep -q 'format_dropdown.set_selected(0)' "$GUI" || die "$GUI : le format JPEG n'est pas le format par defaut."
grep -q 'close-request' "$GUI" || die "$GUI : le bouton/avertissement Quitter est absent."
info "Sources : correctifs Nautilus 4.1, JPEG par defaut et Quitter presents."

DEB="${PKG}_${VERSION}_amd64.deb"
RPM="${PKG}-${VERSION}-1.x86_64.rpm"
DEB_SUM="${DEB}.sha256"
RPM_SUM="${RPM}.sha256"

# ------------------------------------------------------------
# 2. Mise en coherence (planification)
# ------------------------------------------------------------
step "Mise en coherence des fichiers"

TODAY="$(date +%F)"
export VERSION TODAY

RAW_TESTED="${RAW_TESTED:-}"
if [ -z "$RAW_TESTED" ] && grep -q "Le décodage RAW a, lui, été validé" README.fr.md; then
  RAW_TESTED=1   # deja declare lors d'une release precedente (voir README.fr.md)
fi
if [ -z "$RAW_TESTED" ]; then
  if ! $ASSUME_YES && [ -t 0 ]; then
    read -r -p "Un vrai fichier RAW d'appareil photo a-t-il deja ete converti avec succes ? [o/N] " a
    [[ "$a" =~ ^[oOyY]$ ]] && RAW_TESTED=1 || RAW_TESTED=0
  else
    RAW_TESTED=0
  fi
fi
export RAW_TESTED

MAINT=""
if grep -q 'you@example.com' build-deb.sh build-rpm.sh; then
  MAINT="${RELEASE_MAINTAINER:-}"
  if [ -z "$MAINT" ]; then
    GN="$(git config user.name || true)"; GE="$(git config user.email || true)"
    [ -n "$GN" ] && [ -n "$GE" ] || die "MAINTAINER factice dans build-*.sh : definissez RELEASE_MAINTAINER=\"Nom <email>\" (ou git config user.name/user.email)."
    MAINT="$GN <$GE>"
  fi
  case "$MAINT" in
    *\"*|*\$*|*\`*|*\\*) die "RELEASE_MAINTAINER contient un caractere interdit (\" \$ \` \\)." ;;
  esac
  info "MAINTAINER des paquets : $MAINT"
fi
export MAINT

# Patch commun : APPLY=0 liste les changements, APPLY=1 les ecrit.
patch_files() {
  APPLY="$1" python3 -I - <<'PY'
import os, re, sys

apply_ = os.environ["APPLY"] == "1"
version = os.environ["VERSION"]
today = os.environ["TODAY"]
raw_tested = os.environ["RAW_TESTED"] == "1"
first = os.environ["FIRST_RELEASE"] == "true"
maint = os.environ.get("MAINT", "")
changes = []

def patch(path, fn, what):
    if not os.path.exists(path):
        return
    with open(path, encoding="utf-8") as f:
        old = f.read()
    new = fn(old)
    if new != old:
        changes.append(f"{path} : {what}")
        if apply_:
            with open(path, "w", encoding="utf-8") as f:
                f.write(new)

def fix_maint(s):
    if "you@example.com" in s and maint:
        s = re.sub(r'^MAINTAINER=.*$', lambda m: f'MAINTAINER="{maint}"', s, count=1, flags=re.M)
    return re.sub(r'(^URL="[^"]*")[ \t]*# <-- a verifier', r'\1', s, flags=re.M)

def fix_deps(s):
    return (s.replace('--depends "python3-gi"', '--depends "python3-gobject"')
             .replace('--depends "gir1.2-gtk-4.0"', '--depends "gtk4"')
             .replace('--depends "python3-nautilus"', '--depends "nautilus-python"'))

def sync_cargo(s):
    return re.sub(r'^version = ".*"$', f'version = "{version}"', s, count=1, flags=re.M)

def readme(s):
    s = s.replace("Version scaffold v1, fonctionnelle de bout en bout :",
                  "Version stable, fonctionnelle de bout en bout :")
    if raw_tested:
        s = s.replace(
            "**Le décodage RAW n'a pas encore été\n"
            "testé avec un vrai fichier caméra** — à valider avec vos propres fichiers\n"
            "RAW avant une utilisation en production.",
            "Le décodage RAW a, lui, été validé en usage réel avec des fichiers\n"
            "d'appareils photo.")
    return s

def make_changelog(unreleased, first_para, other_para):
    """CHANGELOG.md (anglais, « [Unreleased] ») et CHANGELOG.fr.md (francais,
    « [Non publié] ») : meme logique, textes differents."""
    def changelog(s):
        marker = f"tag `v{version}`"
        if marker in s:
            return s
        has_today = re.search(r'^## ' + re.escape(today) + r'(?:[ \t][^\n]*)?$', s, flags=re.M)
        if first:
            para = first_para.format(marker=marker)
        elif has_today:
            return s  # section du jour déjà rédigée à la main : on n'y touche pas
        else:
            para = other_para.format(marker=marker, tag=f"v{version}")
        if has_today:
            return re.sub(r'(^## ' + re.escape(today) + r'(?:[ \t][^\n]*)?\n)',
                          lambda m: m.group(1) + "\n" + para + "\n", s, count=1, flags=re.M)
        return s.replace(f"## [{unreleased}]\n", f"## [{unreleased}]\n\n## {today}\n\n{para}\n", 1)
    return changelog

changelog_fr = make_changelog(
    "Non publié",
    "Première release stable publiée sur GitHub ({marker}, paquets `.deb` et `.rpm`).",
    "Release stable `{tag}` publiée sur GitHub ({marker}, paquets `.deb` et `.rpm`).")
changelog_en = make_changelog(
    "Unreleased",
    "First stable release published on GitHub ({marker}, `.deb` and `.rpm` packages).",
    "Stable release `{tag}` published on GitHub ({marker}, `.deb` and `.rpm` packages).")

patch("build-deb.sh", fix_maint, "MAINTAINER réel")
patch("build-rpm.sh", fix_maint, "MAINTAINER réel")
patch("build-rpm.sh", fix_deps, "dépendances Fedora/RHEL (python3-gobject, gtk4, nautilus-python)")
patch("Cargo.toml", sync_cargo, f"version = {version}")
patch("README.fr.md", readme, "statut « stable »" + (" + décodage RAW validé" if raw_tested else ""))
patch("CHANGELOG.md", changelog_en, f"entrée {today} (release v{version})")
patch("CHANGELOG.fr.md", changelog_fr, f"entrée {today} (release v{version})")

for c in changes:
    print(c)
PY
}

PLANNED="$(patch_files 0)"
if [ -n "$PLANNED" ]; then
  printf '%s\n' "$PLANNED" | sed 's/^/    a modifier : /'
else
  info "Aucune modification de fichier necessaire."
fi

# ------------------------------------------------------------
# Inspection des paquets existants (utilisee avant ET apres reconstruction)
# ------------------------------------------------------------
PROBLEMS=()
inspect_packages() {
  PROBLEMS=()
  local d eng out v g
  if [ ! -f "$DEB" ]; then
    PROBLEMS+=("$DEB absent")
  else
    v="$(dpkg-deb -f "$DEB" Version)"
    [ "$v" = "$VERSION" ] || PROBLEMS+=("$DEB : champ Version = $v")
    dpkg-deb -f "$DEB" Maintainer | grep -q 'example.com' && PROBLEMS+=("$DEB : maintainer factice")
    d="$(mktemp -d "$WORK/deb.XXXXXX")"
    dpkg-deb -x "$DEB" "$d"
    for f in convert-images-engine convert-images-gui convert_images_nautilus.py; do
      [ -n "$(find "$d" -type f -name "$f" -print -quit)" ] || PROBLEMS+=("$DEB : $f manquant")
    done
    if [ -n "$(find "$d" -type f -name 'convert_images_nautilus.py' -print -quit)" ] \
       && has_nautilus_pin "$(find "$d" -type f -name 'convert_images_nautilus.py' -print -quit)"; then
      PROBLEMS+=("$DEB : extension obsolete (version de Nautilus figee)")
    fi
    g="$(find "$d" -type f -name convert-images-gui -print -quit)"
    if [ -n "$g" ] && { ! grep -q 'format_dropdown.set_selected(0)' "$g" || ! grep -q 'close-request' "$g"; }; then
      PROBLEMS+=("$DEB : IHM obsolete (JPEG par defaut ou Quitter absents)")
    fi
    for po in po/*.po; do
      [ -e "$po" ] || continue
      lang="$(basename "$po" .po)"
      [ -f "$d/usr/share/locale/$lang/LC_MESSAGES/nautilus-convert-images.mo" ] \
        || PROBLEMS+=("$DEB : traduction '$lang' manquante (.mo absent)")
    done
    eng="$(find "$d" -type f -name convert-images-engine -print -quit)"
    if [ -n "$eng" ]; then
      out="$("$eng" --version 2>/dev/null || true)"
      if [ -z "$out" ]; then
        warn "impossible de lire la version du moteur dans le .deb (--version vide)."
      elif ! printf '%s' "$out" | grep -qF "$VERSION"; then
        PROBLEMS+=("$DEB : le moteur annonce '$out' (attendu $VERSION)")
      fi
    fi
  fi
  if [ ! -f "$RPM" ]; then
    PROBLEMS+=("$RPM absent")
  elif command -v rpm >/dev/null 2>&1; then
    rpm -qpR "$RPM" 2>/dev/null | grep -qE '^(python3-gi|gir1\.2-gtk-4\.0|python3-nautilus)( |$)' \
      && PROBLEMS+=("$RPM : dépendances au nom Debian (invalides sur Fedora/RHEL)")
    rpm -qpR "$RPM" 2>/dev/null | grep -qE '^gobject-introspection( |$)' \
      || PROBLEMS+=("$RPM : dépendance gobject-introspection absente (sans elle, l'interface ne démarre pas sur une Fedora minimale)")
    rpm -qp --qf '%{PACKAGER}\n' "$RPM" 2>/dev/null | grep -q 'example.com' \
      && PROBLEMS+=("$RPM : maintainer factice")
    for po in po/*.po; do
      [ -e "$po" ] || continue
      lang="$(basename "$po" .po)"
      rpm -qpl "$RPM" 2>/dev/null | grep -qx "/usr/share/locale/$lang/LC_MESSAGES/nautilus-convert-images.mo" \
        || PROBLEMS+=("$RPM : traduction '$lang' manquante (.mo absent)")
    done
  else
    warn "'rpm' n'est pas installe : contenu du .rpm non inspecte."
  fi
  return 0
}

# Paquets plus anciens que les fichiers qu'ils embarquent ?
stale_sources() {
  local pkg="$1"
  [ -f "$pkg" ] || return 0
  find src nautilus-extension packaging po Cargo.toml Cargo.lock build-deb.sh build-rpm.sh \
       README.md README.fr.md CHANGELOG.md CHANGELOG.fr.md PROJECT_CONTEXT.md PROJECT_CONTEXT.fr.md \
       ARCHITECTURE.md ARCHITECTURE.fr.md CONTRIBUTING.md CONTRIBUTING.fr.md LICENSE \
       -type f -newer "$pkg" -print -quit 2>/dev/null
}

inspect_packages
NEED_REBUILD=false
if [ -n "$PLANNED" ]; then
  NEED_REBUILD=true
  info "Reconstruction necessaire : des fichiers embarques dans les paquets vont changer."
fi
if [ "${#PROBLEMS[@]}" -gt 0 ]; then
  NEED_REBUILD=true
  for p in "${PROBLEMS[@]}"; do info "probleme : $p"; done
fi
for pkg in "$DEB" "$RPM"; do
  s="$(stale_sources "$pkg")"
  if [ -n "$s" ]; then
    NEED_REBUILD=true
    info "$pkg est plus ancien que $s"
  fi
done
$NEED_REBUILD || info "Paquets existants a jour et conformes : ils seront publies tels quels."

# ------------------------------------------------------------
# Notes de release
# ------------------------------------------------------------
NOTES="$WORK/notes.md"

# Les notes sont publiees en ANGLAIS d'abord (le README affiche l'anglais par
# defaut), puis en francais. Sources : la section du jour de CHANGELOG.md
# (anglais) et celle de CHANGELOG.fr.md (francais). Ecrit $WORK/notes_en.md et
# $WORK/notes_fr.md ; sort en erreur, sans rien modifier, si l'une des deux
# sections manque ou est vide.
changelog_notes() {
  python3 -I - "$TODAY" "$WORK" "$TAG" <<'PY'
import os, re, sys
today, work, tag = sys.argv[1:4]
missing = []
for path, name in (("CHANGELOG.md", "notes_en.md"), ("CHANGELOG.fr.md", "notes_fr.md")):
    s = open(path, encoding="utf-8").read()
    m = re.search(r'^## ' + re.escape(today) + r'(?:[ \t][^\n]*)?\n(.*?)(?=^## |\Z)', s, flags=re.M | re.S)
    body = m.group(1).strip() if m else ""
    if not body:
        missing.append(path)
        continue
    with open(os.path.join(work, name), "w", encoding="utf-8") as f:
        f.write(body + "\n")
if missing:
    sys.stderr.write(
        f"\nErreur : section « ## {today} — {tag} » absente ou vide dans : {', '.join(missing)}.\n"
        "Les notes de release sont publiees en anglais (comme le README) puis en francais :\n"
        "CHANGELOG.md (anglais) et CHANGELOG.fr.md (francais) doivent chacun avoir la section\n"
        "du jour, avec le meme titre. Exemple :\n\n"
        f"  ## {today} — {tag}\n\n"
        "  ### Added          (### Ajouté dans CHANGELOG.fr.md)\n\n"
        "  - What changed.\n")
    sys.exit(1)
PY
}

first_release_en() {
cat <<'EOF'
First stable release: **lossless** image conversion straight from the Nautilus (GNOME Files) context menu.

## Features

- **Source formats**: RAW (CR2, CR3, NEF, ARW, DNG, ORF, RAF, RW2, PEF, SRW, X3F…), JPEG, PNG, TIFF, BMP, GIF, WebP — detected by extension then by content, including inside selected folders.
- **Destination formats**: JPEG (default, quality 100), PNG, TIFF, BMP, WebP — full resolution, **no cropping or resizing**; PNG, TIFF, BMP and WebP are lossless.
- **Native GTK4 interface**: real-time detection, choice of format and destination folder (folder creation possible), file-name collision handling, progress and log.
- **Parallel conversion** (Rust engine, pure-Rust RAW decoding, no libraw).
- **Quit button**, with a warning if conversions are still running.
- Compatible with versions 4.0 and 4.1 of the Nautilus library.
EOF
}

first_release_fr() {
cat <<'EOF'
Première release stable : conversion d'images **sans perte** directement depuis le menu contextuel de Nautilus (GNOME Fichiers).

## Fonctionnalités

- **Formats source** : RAW (CR2, CR3, NEF, ARW, DNG, ORF, RAF, RW2, PEF, SRW, X3F…), JPEG, PNG, TIFF, BMP, GIF, WebP — détection par extension puis par contenu, y compris dans les dossiers sélectionnés.
- **Formats de destination** : JPEG (par défaut, qualité 100), PNG, TIFF, BMP, WebP — pleine résolution, **aucun recadrage ni redimensionnement** ; PNG, TIFF, BMP et WebP sont sans perte.
- **Interface GTK4 native** : détection en temps réel, choix du format et du dossier de destination (création de dossier possible), gestion des collisions de noms, progression et journal.
- **Conversion parallèle** (moteur Rust, décodage RAW en Rust pur, sans libraw).
- **Bouton Quitter**, avec avertissement si des conversions sont encore en cours.
- Compatible avec les versions 4.0 et 4.1 de la bibliothèque Nautilus.
EOF
}

install_en() {
cat <<EOF

## Installation

Debian / Ubuntu and derivatives:

\`\`\`bash
sudo apt install ./${DEB}
\`\`\`

Fedora (tested on Fedora 44; \`dnf\` installs the dependencies itself). RHEL 10 family: \`nautilus-python\` comes from EPEL 10 (untested); RHEL, Rocky and AlmaLinux 8 and 9 are not supported (their \`nautilus-python\` is too old):

\`\`\`bash
sudo dnf install ./${RPM}
\`\`\`

Nautilus is restarted automatically at install time to enable the "Convert images…" entry in the context menu ("Convertir les images…" in French; the interface is also available in Spanish and German).

Verify the downloads (each package and its \`.sha256\` file in the same folder):

\`\`\`bash
sha256sum -c ${DEB_SUM}
sha256sum -c ${RPM_SUM}
\`\`\`
EOF
}

install_fr() {
cat <<EOF

## Installation

Debian / Ubuntu et dérivés :

\`\`\`bash
sudo apt install ./${DEB}
\`\`\`

Fedora (testé sur Fedora 44 ; \`dnf\` installe lui-même les dépendances). Famille RHEL 10 : \`nautilus-python\` vient d'EPEL 10 (non testé) ; RHEL, Rocky et AlmaLinux 8 et 9 ne sont pas pris en charge (leur \`nautilus-python\` est trop ancien) :

\`\`\`bash
sudo dnf install ./${RPM}
\`\`\`

Nautilus est redémarré automatiquement à l'installation pour activer l'entrée « Convertir les images… » du menu contextuel (« Convert images… » en anglais ; l'interface existe aussi en espagnol et en allemand).

Vérification des téléchargements (le paquet et son fichier \`.sha256\` dans le même dossier) :

\`\`\`bash
sha256sum -c ${DEB_SUM}
sha256sum -c ${RPM_SUM}
\`\`\`
EOF
}

if ! $FIRST_RELEASE; then
  changelog_notes || exit 1
fi

{
printf '# %s %s\n\n' "$PKG" "$TAG"
# --- English ---
if $FIRST_RELEASE; then
  first_release_en
else
  printf "## What's new since %s\n\n" "$PREV_TAG"
  cat "$WORK/notes_en.md"
fi
install_en
if [ "$RAW_TESTED" != "1" ]; then
cat <<EOF

## Known limitation

RAW decoding uses \`rawloader\`, then LibRaw as a fallback for cameras the first one does not know. Color fidelity has only been checked on a limited number of camera models: please report any rejected file or doubtful colors via the [issues](https://github.com/${REPO_SLUG}/issues), mentioning the camera model.
EOF
fi
cat <<EOF

See the [CHANGELOG](https://github.com/${REPO_SLUG}/blob/main/CHANGELOG.md) for details.

---

# Version française

EOF
# --- Français ---
if $FIRST_RELEASE; then
  first_release_fr
else
  printf '## Nouveautés depuis %s\n\n' "$PREV_TAG"
  cat "$WORK/notes_fr.md"
fi
install_fr
if [ "$RAW_TESTED" != "1" ]; then
cat <<EOF

## Limite connue

Le décodage RAW utilise \`rawloader\`, puis LibRaw en secours pour les boîtiers inconnus du premier. La fidélité des couleurs n'a été vérifiée que sur un nombre limité de boîtiers : signalez tout fichier refusé ou aux couleurs douteuses via les [issues](https://github.com/${REPO_SLUG}/issues), en indiquant le modèle d'appareil.
EOF
fi
cat <<EOF

Voir le [CHANGELOG](https://github.com/${REPO_SLUG}/blob/main/CHANGELOG.fr.md) pour le détail.
EOF
} > "$NOTES"

step "Notes de release (aperçu)"
sed 's/^/    | /' "$NOTES"

# ------------------------------------------------------------
# Plan et confirmation
# ------------------------------------------------------------
step "Plan"
info "1. $($NEED_REBUILD && echo 'reconstruire .deb et .rpm (build-*.sh --no-version-change --yes)' || echo 'aucune reconstruction')"
info "2. commit + push de main (etat actuel :)"
git status --short | sed 's/^/         /'
info "3. creer la release $TAG (apres ${PREV_TAG:-aucune release precedente}) sur $REPO_SLUG (stable, 'latest') avec : $DEB, $RPM, $DEB_SUM, $RPM_SUM"

if $DRY_RUN; then
  printf '\n[dry-run] Rien n'"'"'a ete modifie, committe, pousse ni publie.\n'
  exit 0
fi

if ! $ASSUME_YES; then
  [ -t 0 ] || die "pas de terminal interactif : relancez avec --yes."
  read -r -p $'\nPublier la release '"$TAG"$' ? [o/N] ' a
  [[ "$a" =~ ^[oOyY]$ ]] || { echo "Annule. Rien n'a ete modifie."; exit 0; }
fi

# ------------------------------------------------------------
# 3. Application + reconstruction
# ------------------------------------------------------------
step "Application des modifications"
if [ -n "$PLANNED" ]; then
  patch_files 1 | sed 's/^/    modifie : /'
fi

if $NEED_REBUILD; then
  for t in cargo fpm rpmbuild; do
    command -v "$t" >/dev/null 2>&1 || die "outil manquant pour reconstruire les paquets : $t"
  done
  step "Reconstruction du .deb"
  ./build-deb.sh --no-version-change --yes
  step "Reconstruction du .rpm"
  ./build-rpm.sh --no-version-change --yes
  [ "$(tr -d '[:space:]' < VERSION)" = "$VERSION" ] || die "VERSION a change pendant le build."
  inspect_packages
  if [ "${#PROBLEMS[@]}" -gt 0 ]; then
    for p in "${PROBLEMS[@]}"; do warn "$p"; done
    die "les paquets reconstruits ne sont pas conformes : release annulee (rien n'est pousse)."
  fi
  info "Paquets reconstruits et verifies."
fi

sha256sum "$DEB" > "$WORK/$DEB_SUM"
sha256sum "$RPM" > "$WORK/$RPM_SUM"

# ------------------------------------------------------------
# 4. Commit + push
# ------------------------------------------------------------
step "Commit et push sur main"
if [ -n "$(git status --porcelain)" ]; then
  git add -A
  if $FIRST_RELEASE; then
    git commit -q -m "Release $TAG" \
               -m "Correctifs Nautilus 4.1 (typelib), JPEG par défaut, bouton Quitter avec avertissement, dépendances RPM Fedora/RHEL, maintainer réel et documentation à jour."
  else
    git commit -q -m "Release $TAG" -m "Voir CHANGELOG.md et CHANGELOG.fr.md."
  fi
  info "Commit créé : $(git rev-parse --short HEAD)"
else
  info "Rien à valider."
fi
if [ "$(git rev-list --count origin/main..HEAD)" != "0" ]; then
  git push origin main
fi
SHA="$(git rev-parse HEAD)"
REMOTE_SHA="$(git ls-remote origin refs/heads/main | cut -f1)"
[ "$REMOTE_SHA" = "$SHA" ] || die "origin/main ($REMOTE_SHA) != HEAD local ($SHA) : release annulee."
info "origin/main = $SHA"

# ------------------------------------------------------------
# 5. Release
# ------------------------------------------------------------
step "Creation de la release $TAG"
gh release create "$TAG" "$DEB" "$RPM" "$WORK/$DEB_SUM" "$WORK/$RPM_SUM" \
  --repo "$REPO_SLUG" \
  --target "$SHA" \
  --title "$PKG $TAG" \
  --notes-file "$NOTES" \
  --latest

git fetch --quiet --tags origin || true

step "Verification"
STATE="$(gh release view "$TAG" --repo "$REPO_SLUG" --json isDraft,isPrerelease,url --jq '"\(.isDraft) \(.isPrerelease) \(.url)"')"
read -r IS_DRAFT IS_PRE URL <<< "$STATE"
[ "$IS_DRAFT" = "false" ] && [ "$IS_PRE" = "false" ] || die "la release n'est pas une release stable publiee (draft=$IS_DRAFT, prerelease=$IS_PRE)."
ASSETS="$(gh release view "$TAG" --repo "$REPO_SLUG" --json assets --jq '.assets[].name')"
for a in "$DEB" "$RPM" "$DEB_SUM" "$RPM_SUM"; do
  printf '%s\n' "$ASSETS" | grep -qxF "$a" || die "fichier absent de la release : $a"
done
echo ""
echo "Release stable publiee : $URL"
printf '%s\n' "$ASSETS" | sed 's/^/   /'
echo ""
echo "Annulation si besoin : gh release delete $TAG --repo $REPO_SLUG --cleanup-tag"
