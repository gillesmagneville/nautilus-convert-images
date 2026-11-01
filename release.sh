#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

# ============================================================
# nautilus-convert-images - release.sh
#
# Publishes the stable GitHub release matching the content of VERSION:
#   1. preliminary checks (branch, remote, free tag, fixes present)
#   2. consistency updates (MAINTAINER, .rpm dependencies, Cargo.toml, README,
#      CHANGELOG), then rebuilding the packages if needed
#   3. checking the content of the packages (.deb / .rpm)
#   4. commit + push to main
#   5. creating the release (tag, notes, .deb, .rpm, one .sha256 per package)
#
# The release notes are published in English first (the README shows English
# by default), then in French. They come from today's dated section of
# CHANGELOG.md (English) and CHANGELOG.fr.md (French): both are required.
#
# Run from the root of the repository, after the usual builds.
# Use --dry-run to see everything without modifying or publishing anything.
# ============================================================

REPO_SLUG="gillesmagneville/nautilus-convert-images"
PKG="nautilus-convert-images"
DRY_RUN=false
ASSUME_YES=false

show_help() {
  cat <<EOF
Usage: ./release.sh [options]

Publishes the stable GitHub release of nautilus-convert-images (tag v\$(cat VERSION)).

  --dry-run    Show what would be done (and the release notes) without
               modifying, committing, pushing or publishing anything
  --yes, -y    Do not ask for confirmation (useful variables:
               RAW_TESTED=1 if a real RAW file was converted successfully,
               RELEASE_MAINTAINER="Name <email>" for the maintainer field)
  --help, -h   Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --yes|-y) ASSUME_YES=true; shift ;;
    --help|-h) show_help; exit 0 ;;
    *) echo "Unknown option: $1" >&2; show_help >&2; exit 1 ;;
  esac
done

step() { printf '\n>>> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
die()  { printf '\nError: %s\n' "$*" >&2; exit 1; }

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ------------------------------------------------------------
# 1. Preliminary checks
# ------------------------------------------------------------
step "Preliminary checks"

for t in git gh python3 sha256sum dpkg-deb tar; do
  command -v "$t" >/dev/null 2>&1 || die "missing tool: $t"
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "this folder is not a git repository."
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || die "the current branch is not 'main'."

ORIGIN_URL="$(git remote get-url origin 2>/dev/null)" || die "no 'origin' remote."
case "$ORIGIN_URL" in
  *"$REPO_SLUG"*) ;;
  *) die "origin does not point to $REPO_SLUG ($ORIGIN_URL)." ;;
esac

if ! gh auth status >/dev/null 2>&1; then
  if $DRY_RUN; then
    warn "gh is not authenticated (run 'gh auth login' before the real publication)."
  else
    die "gh is not authenticated: run 'gh auth login'."
  fi
fi

git fetch --quiet --tags origin || die "git fetch origin failed."
if git rev-parse -q --verify origin/main >/dev/null; then
  BEHIND="$(git rev-list --count HEAD..origin/main)"
  [ "$BEHIND" = "0" ] || die "origin/main has $BEHIND commit(s) missing locally: run 'git pull --rebase' first."
fi

[ -f VERSION ] || die "VERSION file not found."
VERSION="$(tr -d '[:space:]' < VERSION)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid VERSION: '$VERSION' (expected X.Y.Z)."
TAG="v$VERSION"
PREV_TAG="$(git tag -l 'v[0-9]*' --sort=-v:refname | grep -vxF "$TAG" | head -1 || true)"
if [ -n "$PREV_TAG" ]; then
  FIRST_RELEASE=false
  [ "$(printf '%s\n%s\n' "${PREV_TAG#v}" "$VERSION" | sort -V | tail -1)" = "$VERSION" ] \
    || die "VERSION ($VERSION) is not greater than the latest release ($PREV_TAG)."
  info "Version: $VERSION  ->  tag $TAG  (latest release: $PREV_TAG)"
else
  FIRST_RELEASE=true
  info "Version: $VERSION  ->  tag $TAG  (first release)"
fi
export FIRST_RELEASE

# If VERSION is already published, it is almost always because the move to the
# next version was forgotten: say what to do (VERSION only advances through a
# successful build, see CHANGELOG.md).
NEXT_HINT="VERSION ($VERSION) is already published. To move on to the next version, first run:
    ./build-deb.sh --patch --yes     (or --minor / --major instead of --patch)
    ./build-rpm.sh --no-version-change --yes
  then run ./release.sh again."
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  die "tag $TAG already exists locally.
  $NEXT_HINT"
fi
if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
  die "tag $TAG already exists on GitHub.
  $NEXT_HINT"
fi
if gh release view "$TAG" --repo "$REPO_SLUG" >/dev/null 2>&1; then
  die "a release $TAG already exists on GitHub.
  $NEXT_HINT"
fi

# True if the file pins the Nautilus version with an ACTIVE statement
# (comment lines that quote the statement do not count).
has_nautilus_pin() {
  grep -Eq '^[[:space:]]*gi\.require_version\([[:space:]]*["'"'"']Nautilus["'"'"']' "$1"
}

EXT="nautilus-extension/convert_images_nautilus.py"
GUI="nautilus-extension/convert-images-gui"
[ -f "$EXT" ] && [ -f "$GUI" ] || die "extension or GUI not found in nautilus-extension/."
if has_nautilus_pin "$EXT"; then
  die "$EXT still pins the Nautilus version (Nautilus 4.1 fix missing)."
fi
grep -q 'format_dropdown.set_selected(0)' "$GUI" || die "$GUI: JPEG is not the default format."
grep -q 'close-request' "$GUI" || die "$GUI: the Quit button/warning is missing."
info "Sources: Nautilus 4.1 fix, JPEG by default and Quit button present."

DEB="${PKG}_${VERSION}_amd64.deb"
RPM="${PKG}-${VERSION}-1.x86_64.rpm"
DEB_SUM="${DEB}.sha256"
RPM_SUM="${RPM}.sha256"

# ------------------------------------------------------------
# 2. Consistency updates (planning)
# ------------------------------------------------------------
step "Consistency updates"

TODAY="$(date +%F)"
export VERSION TODAY

RAW_TESTED="${RAW_TESTED:-}"
if [ -z "$RAW_TESTED" ] && grep -q "Le décodage RAW a, lui, été validé" README.fr.md; then
  RAW_TESTED=1   # already declared in a previous release (see README.fr.md)
fi
if [ -z "$RAW_TESTED" ]; then
  if ! $ASSUME_YES && [ -t 0 ]; then
    read -r -p "Has a real RAW file from a camera already been converted successfully? [y/N] " a
    [[ "$a" =~ ^[yY]$ ]] && RAW_TESTED=1 || RAW_TESTED=0
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
    [ -n "$GN" ] && [ -n "$GE" ] || die "placeholder MAINTAINER in build-*.sh: set RELEASE_MAINTAINER=\"Name <email>\" (or git config user.name/user.email)."
    MAINT="$GN <$GE>"
  fi
  case "$MAINT" in
    *\"*|*\$*|*\`*|*\\*) die "RELEASE_MAINTAINER contains a forbidden character (\" \$ \` \\)." ;;
  esac
  info "Package MAINTAINER: $MAINT"
fi
export MAINT

# Common patch: APPLY=0 lists the changes, APPLY=1 writes them.
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
    return re.sub(r'(^URL="[^"]*")[ \t]*# <-- to check', r'\1', s, flags=re.M)

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
    """CHANGELOG.md (English, "[Unreleased]") and CHANGELOG.fr.md (French,
    "[Non publié]"): same logic, different texts."""
    def changelog(s):
        marker = f"tag `v{version}`"
        if marker in s:
            return s
        has_today = re.search(r'^## ' + re.escape(today) + r'(?:[ \t][^\n]*)?$', s, flags=re.M)
        if first:
            para = first_para.format(marker=marker)
        elif has_today:
            return s  # today's section already written by hand: leave it alone
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

patch("build-deb.sh", fix_maint, "real MAINTAINER")
patch("build-rpm.sh", fix_maint, "real MAINTAINER")
patch("build-rpm.sh", fix_deps, "Fedora/RHEL dependencies (python3-gobject, gtk4, nautilus-python)")
patch("Cargo.toml", sync_cargo, f"version = {version}")
patch("README.fr.md", readme, "'stable' status" + (" + RAW decoding validated" if raw_tested else ""))
patch("CHANGELOG.md", changelog_en, f"{today} entry (release v{version})")
patch("CHANGELOG.fr.md", changelog_fr, f"{today} entry (release v{version})")

for c in changes:
    print(c)
PY
}

PLANNED="$(patch_files 0)"
if [ -n "$PLANNED" ]; then
  printf '%s\n' "$PLANNED" | sed 's/^/    to modify: /'
else
  info "No file change needed."
fi

# ------------------------------------------------------------
# Inspection of the existing packages (used before AND after rebuilding)
# ------------------------------------------------------------
PROBLEMS=()
inspect_packages() {
  PROBLEMS=()
  local d eng out v g
  if [ ! -f "$DEB" ]; then
    PROBLEMS+=("$DEB missing")
  else
    v="$(dpkg-deb -f "$DEB" Version)"
    [ "$v" = "$VERSION" ] || PROBLEMS+=("$DEB: Version field = $v")
    dpkg-deb -f "$DEB" Maintainer | grep -q 'example.com' && PROBLEMS+=("$DEB: placeholder maintainer")
    d="$(mktemp -d "$WORK/deb.XXXXXX")"
    dpkg-deb -x "$DEB" "$d"
    for f in convert-images-engine convert-images-gui convert_images_nautilus.py; do
      [ -n "$(find "$d" -type f -name "$f" -print -quit)" ] || PROBLEMS+=("$DEB: $f missing")
    done
    if [ -n "$(find "$d" -type f -name 'convert_images_nautilus.py' -print -quit)" ] \
       && has_nautilus_pin "$(find "$d" -type f -name 'convert_images_nautilus.py' -print -quit)"; then
      PROBLEMS+=("$DEB: outdated extension (Nautilus version pinned)")
    fi
    g="$(find "$d" -type f -name convert-images-gui -print -quit)"
    if [ -n "$g" ] && { ! grep -q 'format_dropdown.set_selected(0)' "$g" || ! grep -q 'close-request' "$g"; }; then
      PROBLEMS+=("$DEB: outdated GUI (JPEG default or Quit button missing)")
    fi
    for po in po/*.po; do
      [ -e "$po" ] || continue
      lang="$(basename "$po" .po)"
      [ -f "$d/usr/share/locale/$lang/LC_MESSAGES/nautilus-convert-images.mo" ] \
        || PROBLEMS+=("$DEB: '$lang' translation missing (.mo absent)")
    done
    for c in CODE_OF_CONDUCT.md CODE_OF_CONDUCT.fr.md; do
      [ -f "$d/usr/share/doc/$PKG/$c" ] || PROBLEMS+=("$DEB: $c missing")
    done
    eng="$(find "$d" -type f -name convert-images-engine -print -quit)"
    if [ -n "$eng" ]; then
      out="$("$eng" --version 2>/dev/null || true)"
      if [ -z "$out" ]; then
        warn "cannot read the engine version in the .deb (empty --version)."
      elif ! printf '%s' "$out" | grep -qF "$VERSION"; then
        PROBLEMS+=("$DEB: the engine reports '$out' (expected $VERSION)")
      fi
    fi
  fi
  if [ ! -f "$RPM" ]; then
    PROBLEMS+=("$RPM missing")
  elif command -v rpm >/dev/null 2>&1; then
    rpm -qpR "$RPM" 2>/dev/null | grep -qE '^(python3-gi|gir1\.2-gtk-4\.0|python3-nautilus)( |$)' \
      && PROBLEMS+=("$RPM: Debian-named dependencies (invalid on Fedora/RHEL)")
    rpm -qpR "$RPM" 2>/dev/null | grep -qE '^gobject-introspection( |$)' \
      || PROBLEMS+=("$RPM: gobject-introspection dependency missing (without it, the GUI does not start on a minimal Fedora)")
    rpm -qp --qf '%{PACKAGER}\n' "$RPM" 2>/dev/null | grep -q 'example.com' \
      && PROBLEMS+=("$RPM: placeholder maintainer")
    for c in CODE_OF_CONDUCT.md CODE_OF_CONDUCT.fr.md; do
      rpm -qpl "$RPM" 2>/dev/null | grep -qx "/usr/share/doc/$PKG/$c" \
        || PROBLEMS+=("$RPM: $c missing")
    done
    for po in po/*.po; do
      [ -e "$po" ] || continue
      lang="$(basename "$po" .po)"
      rpm -qpl "$RPM" 2>/dev/null | grep -qx "/usr/share/locale/$lang/LC_MESSAGES/nautilus-convert-images.mo" \
        || PROBLEMS+=("$RPM: '$lang' translation missing (.mo absent)")
    done
  else
    warn "'rpm' is not installed: the content of the .rpm was not inspected."
  fi
  return 0
}

# Packages older than the files they embed?
stale_sources() {
  local pkg="$1"
  [ -f "$pkg" ] || return 0
  find src nautilus-extension packaging po Cargo.toml Cargo.lock build-deb.sh build-rpm.sh \
       README.md README.fr.md CHANGELOG.md CHANGELOG.fr.md PROJECT_CONTEXT.md PROJECT_CONTEXT.fr.md \
       ARCHITECTURE.md ARCHITECTURE.fr.md CONTRIBUTING.md CONTRIBUTING.fr.md \
       CODE_OF_CONDUCT.md CODE_OF_CONDUCT.fr.md LICENSE \
       -type f -newer "$pkg" -print -quit 2>/dev/null
}

inspect_packages
NEED_REBUILD=false
if [ -n "$PLANNED" ]; then
  NEED_REBUILD=true
  info "Rebuild needed: files embedded in the packages are going to change."
fi
if [ "${#PROBLEMS[@]}" -gt 0 ]; then
  NEED_REBUILD=true
  for p in "${PROBLEMS[@]}"; do info "problem: $p"; done
fi
for pkg in "$DEB" "$RPM"; do
  s="$(stale_sources "$pkg")"
  if [ -n "$s" ]; then
    NEED_REBUILD=true
    info "$pkg is older than $s"
  fi
done
$NEED_REBUILD || info "Existing packages are up to date and compliant: they will be published as they are."

# ------------------------------------------------------------
# Release notes
# ------------------------------------------------------------
NOTES="$WORK/notes.md"

# The notes are published in ENGLISH first (the README shows English by
# default), then in French. Sources: today's section of CHANGELOG.md (English)
# and of CHANGELOG.fr.md (French). Writes $WORK/notes_en.md and
# $WORK/notes_fr.md; exits with an error, modifying nothing, if either section
# is missing or empty.
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
        f"\nError: section \"## {today} — {tag}\" missing or empty in: {', '.join(missing)}.\n"
        "The release notes are published in English (like the README), then in French:\n"
        "CHANGELOG.md (English) and CHANGELOG.fr.md (French) must each have today's\n"
        "section, with the same title. Example:\n\n"
        f"  ## {today} — {tag}\n\n"
        "  ### Added          (### Ajouté in CHANGELOG.fr.md)\n\n"
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

step "Release notes (preview)"
sed 's/^/    | /' "$NOTES"

# ------------------------------------------------------------
# Plan and confirmation
# ------------------------------------------------------------
step "Plan"
info "1. $($NEED_REBUILD && echo 'rebuild .deb and .rpm (build-*.sh --no-version-change --yes)' || echo 'no rebuild')"
info "2. commit + push of main (current state:)"
git status --short | sed 's/^/         /'
info "3. create release $TAG (after ${PREV_TAG:-no previous release}) on $REPO_SLUG (stable, 'latest') with: $DEB, $RPM, $DEB_SUM, $RPM_SUM"

if $DRY_RUN; then
  printf '\n[dry-run] Nothing was modified, committed, pushed or published.\n'
  exit 0
fi

if ! $ASSUME_YES; then
  [ -t 0 ] || die "no interactive terminal: run again with --yes."
  read -r -p $'\nPublish release '"$TAG"$'? [y/N] ' a
  [[ "$a" =~ ^[yY]$ ]] || { echo "Cancelled. Nothing was modified."; exit 0; }
fi

# ------------------------------------------------------------
# 3. Applying + rebuilding
# ------------------------------------------------------------
step "Applying the changes"
if [ -n "$PLANNED" ]; then
  patch_files 1 | sed 's/^/    modified: /'
fi

if $NEED_REBUILD; then
  for t in cargo fpm rpmbuild; do
    command -v "$t" >/dev/null 2>&1 || die "missing tool to rebuild the packages: $t"
  done
  step "Rebuilding the .deb"
  ./build-deb.sh --no-version-change --yes
  step "Rebuilding the .rpm"
  ./build-rpm.sh --no-version-change --yes
  [ "$(tr -d '[:space:]' < VERSION)" = "$VERSION" ] || die "VERSION changed during the build."
  inspect_packages
  if [ "${#PROBLEMS[@]}" -gt 0 ]; then
    for p in "${PROBLEMS[@]}"; do warn "$p"; done
    die "the rebuilt packages are not compliant: release cancelled (nothing was pushed)."
  fi
  info "Packages rebuilt and checked."
fi

sha256sum "$DEB" > "$WORK/$DEB_SUM"
sha256sum "$RPM" > "$WORK/$RPM_SUM"

# ------------------------------------------------------------
# 4. Commit + push
# ------------------------------------------------------------
step "Commit and push to main"
if [ -n "$(git status --porcelain)" ]; then
  git add -A
  if $FIRST_RELEASE; then
    git commit -q -m "Release $TAG" \
               -m "Nautilus 4.1 fixes (typelib), JPEG by default, Quit button with a warning, Fedora/RHEL RPM dependencies, real maintainer and up-to-date documentation."
  else
    git commit -q -m "Release $TAG" -m "See CHANGELOG.md and CHANGELOG.fr.md."
  fi
  info "Commit created: $(git rev-parse --short HEAD)"
else
  info "Nothing to commit."
fi
if [ "$(git rev-list --count origin/main..HEAD)" != "0" ]; then
  git push origin main
fi
SHA="$(git rev-parse HEAD)"
REMOTE_SHA="$(git ls-remote origin refs/heads/main | cut -f1)"
[ "$REMOTE_SHA" = "$SHA" ] || die "origin/main ($REMOTE_SHA) != local HEAD ($SHA): release cancelled."
info "origin/main = $SHA"

# ------------------------------------------------------------
# 5. Release
# ------------------------------------------------------------
step "Creating release $TAG"
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
[ "$IS_DRAFT" = "false" ] && [ "$IS_PRE" = "false" ] || die "the release is not a published stable release (draft=$IS_DRAFT, prerelease=$IS_PRE)."
ASSETS="$(gh release view "$TAG" --repo "$REPO_SLUG" --json assets --jq '.assets[].name')"
for a in "$DEB" "$RPM" "$DEB_SUM" "$RPM_SUM"; do
  printf '%s\n' "$ASSETS" | grep -qxF "$a" || die "file missing from the release: $a"
done
echo ""
echo "Stable release published: $URL"
printf '%s\n' "$ASSETS" | sed 's/^/   /'
echo ""
echo "To undo if needed: gh release delete $TAG --repo $REPO_SLUG --cleanup-tag"
