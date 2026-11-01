#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

# ============================================================
# nautilus-convert-images - build-deb.sh
#
# Builds a .deb package (Debian, Ubuntu, ...) with fpm.
# Same principles as linuxdoctor's build-deb.sh:
#   - version bumped interactively or with a flag (--major/--minor/--patch)
#   - VERSION and Cargo.toml updated only after a successful build
#   - clean staging in a temporary folder, normalized permissions
#
# Difference from linuxdoctor: two programs to stage (the Rust engine and
# the GTK4 GUI in Python, the latter copied as is, without compilation),
# plus the nautilus-python extension and the .desktop file, plus the
# translations (po/*.po compiled to .mo with msgfmt).
# ============================================================

PACKAGE_NAME="nautilus-convert-images"
MAINTAINER="Gilles MAGNEVILLE <gilles@magneville.fr>"
DESCRIPTION="Lossless image conversion (RAW, JPEG, PNG, TIFF, BMP, WebP), built into the Nautilus context menu"
URL="https://github.com/gillesmagneville/nautilus-convert-images"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$HOME/nautilus-convert-images-build/deb"
VERSION_FILE="$PROJECT_DIR/VERSION"
CARGO_TOML="$PROJECT_DIR/Cargo.toml"

show_help() {
  cat <<EOF
Usage: ./build-deb.sh [options]

Builds a .deb package for nautilus-convert-images.

  --major               Bump the major number (1.2.3 -> 2.0.0)
  --minor               Bump the minor number (1.2.3 -> 1.3.0)
  --patch               Bump the patch number (1.2.3 -> 1.2.4)
  --no-version-change   Rebuild without changing the version
  --yes, -y             Do not ask for confirmation before building
  --clean               Remove the build folder and the generated .deb files
  --help, -h            Show this help

Without a version option: interactive mode (needs a terminal).
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
    *) echo "Unknown option: $1"; show_help; exit 1 ;;
  esac
done

if [ "$CLEAN" = true ]; then
  echo ">>> Cleaning the build folder and the generated .deb files..."
  rm -rf "$BUILD_DIR"
  rm -f "$PROJECT_DIR"/*.deb
  echo ">>> Done."
  exit 0
fi

# --- Checking the required tools ---
if ! command -v fpm &> /dev/null; then
  echo "Error: fpm is not installed."
  echo "Install it with: gem install --user-install fpm"
  exit 1
fi
if ! command -v cargo &> /dev/null; then
  echo "Error: cargo (Rust) is not installed. See https://rustup.rs"
  exit 1
fi
if ! command -v msgfmt &> /dev/null; then
  echo "Error: msgfmt (GNU gettext tools) not found: it compiles the"
  echo "translations (po/*.po) included in the package."
  echo "On Debian/Ubuntu:                sudo apt install gettext"
  echo "On Fedora/RHEL/Rocky/AlmaLinux:  sudo dnf install gettext"
  echo "On openSUSE:                     sudo zypper install gettext-tools"
  exit 1
fi
if ! command -v dpkg-deb &> /dev/null; then
  echo "Error: dpkg-deb not found (needed to generate a .deb)."
  exit 1
fi

# --- Reading the current version ---
CURRENT_VERSION="0.1.0"
[ -f "$VERSION_FILE" ] && CURRENT_VERSION=$(tr -d '[:space:]' < "$VERSION_FILE")

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
MAJOR=${MAJOR:-0}; MINOR=${MINOR:-0}; PATCH=${PATCH:-0}

# --- Interactive mode if no version argument was given ---
# With no version flag AND no interactive terminal, there is no way to
# know what to do: better to fail clearly here than to let `read` hit a
# silent EOF further down (which, with `set -e`, killed the script
# without a message before even compiling -- VERSION and Cargo.toml were
# therefore left unchanged with no explanation).
if [ -z "$INCREMENT" ] && [ "$NO_VERSION_CHANGE" = false ]; then
  if [ ! -t 0 ]; then
    echo "Error: no version flag given (--major/--minor/--patch/"
    echo "--no-version-change) and no interactive terminal available for"
    echo "the choice menu. Run again with one of these flags."
    exit 1
  fi
  echo ""
  echo "Current version: $CURRENT_VERSION"
  echo ""
  echo "  1) major (-> $((MAJOR + 1)).0.0)"
  echo "  2) minor (-> $MAJOR.$((MINOR + 1)).0)"
  echo "  3) patch (-> $MAJOR.$MINOR.$((PATCH + 1)))"
  echo "  4) no-version-change (rebuild as $CURRENT_VERSION)"
  echo ""
  read -p "Choice [1/2/3/4]: " CHOICE
  case $CHOICE in
    1) INCREMENT="major" ;;
    2) INCREMENT="minor" ;;
    3) INCREMENT="patch" ;;
    4) NO_VERSION_CHANGE=true ;;
    *) echo "Invalid choice. Cancelled."; exit 1 ;;
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
echo " Package  : $PACKAGE_NAME"
echo " Version  : $CURRENT_VERSION -> $NEW_VERSION"
echo " Format   : .deb"
echo "========================================"
echo ""
# At this point, either a version flag was given explicitly (in which
# case stdin may be non-interactive: that is a legitimate scripted/CI
# use), or the interactive menu above has already confirmed that a
# terminal is available. Only ask for confirmation if an answer can
# actually be read -- otherwise `read` fails silently on EOF and, with
# `set -e`, killed the script without a message before even compiling.
if [ "$ASSUME_YES" = true ]; then
  echo "Automatic confirmation (--yes)."
elif [ -t 0 ]; then
  read -p "Build? [y/N] " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[yY]$ ]]; then
    echo "Build cancelled. No file was modified."
    exit 0
  fi
else
  echo "No interactive terminal: automatic confirmation (a version flag was given explicitly)."
fi

# --- Temporary update of Cargo.toml BEFORE compiling, so that the binary
#     embeds the right number through `convert-images-engine --version`
#     (clap reads CARGO_PKG_VERSION at compile time). Reverted if a step
#     fails. ---
if [ "$NEW_VERSION" != "$CURRENT_VERSION" ]; then
  sed -i "s/^version = \".*\"/version = \"$NEW_VERSION\"/" "$CARGO_TOML"
fi

echo ""
echo ">>> Compiling in release mode (cargo build --release)..."
BUILD_LOG=$(mktemp)
if (cd "$PROJECT_DIR" && cargo build --release --quiet) > "$BUILD_LOG" 2>&1; then
  rm -f "$BUILD_LOG"
  echo ">>> Compilation succeeded."
else
  echo ""
  echo "Error: the compilation failed."
  echo ""
  sed 's/^/  /' "$BUILD_LOG"
  rm -f "$BUILD_LOG"
  sed -i "s/^version = \".*\"/version = \"$CURRENT_VERSION\"/" "$CARGO_TOML"
  echo ""
  echo "Build cancelled: Cargo.toml restored, no package generated."
  exit 1
fi

ENGINE_BINARY="$PROJECT_DIR/target/release/convert-images-engine"
if [ ! -f "$ENGINE_BINARY" ]; then
  echo "Error: engine binary not found after compilation ($ENGINE_BINARY)."
  sed -i "s/^version = \".*\"/version = \"$CURRENT_VERSION\"/" "$CARGO_TOML"
  exit 1
fi

# --- Staging ---
echo ">>> Creating the staging tree..."
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

# Translations: each po/<language>.po is compiled to a .mo (the binary format
# read by gettext) and installed in /usr/share/locale/<language>/LC_MESSAGES/.
# The .mo file name must be identical to the gettext domain declared in the
# GUI and in the extension (I18N_DOMAIN = "nautilus-convert-images").
# --check rejects a catalog whose {…} fields do not match.
echo ">>> Compiling the translations (msgfmt)..."
I18N_DOMAIN="nautilus-convert-images"
I18N_COUNT=0
for po in "$PROJECT_DIR"/po/*.po; do
  [ -e "$po" ] || continue
  lang="$(basename "$po" .po)"
  mkdir -p "$BUILD_DIR/usr/share/locale/$lang/LC_MESSAGES"
  if ! msgfmt --check -o "$BUILD_DIR/usr/share/locale/$lang/LC_MESSAGES/$I18N_DOMAIN.mo" "$po"; then
    echo "Error: could not compile $po."
    sed -i "s/^version = \".*\"/version = \"$CURRENT_VERSION\"/" "$CARGO_TOML"
    rm -rf "$BUILD_DIR"
    echo "Build cancelled: Cargo.toml restored, no package generated."
    exit 1
  fi
  I18N_COUNT=$((I18N_COUNT + 1))
done
if [ "$I18N_COUNT" -eq 0 ]; then
  echo "Error: no po/*.po catalog found: the package would have no translation."
  sed -i "s/^version = \".*\"/version = \"$CURRENT_VERSION\"/" "$CARGO_TOML"
  rm -rf "$BUILD_DIR"
  exit 1
fi
echo "    $I18N_COUNT language(s) installed."
# The code of conduct (Contributor Covenant 3.0) is under CC-BY-SA-4.0, hence
# the license expression given to fpm below.
for doc in README.md README.fr.md CHANGELOG.md CHANGELOG.fr.md PROJECT_CONTEXT.md PROJECT_CONTEXT.fr.md ARCHITECTURE.md ARCHITECTURE.fr.md CONTRIBUTING.md CONTRIBUTING.fr.md CODE_OF_CONDUCT.md CODE_OF_CONDUCT.fr.md LICENSE; do
  [ -f "$PROJECT_DIR/$doc" ] && cp "$PROJECT_DIR/$doc" "$BUILD_DIR/usr/share/doc/$PACKAGE_NAME/"
done

# Permission normalization: cp applies the build machine's current umask,
# not the permissions of the source. Consistent permissions are therefore
# forced, as in linuxdoctor's build-deb.sh.
echo ">>> Normalizing permissions..."
find "$BUILD_DIR" -type d -exec chmod 755 {} +
find "$BUILD_DIR" -type f -exec chmod 644 {} +
chmod +x "$BUILD_DIR/usr/bin/convert-images-engine"
chmod +x "$BUILD_DIR/usr/bin/convert-images-gui"

# --- Building the package ---
echo ""
echo ">>> Building the .deb package (fpm)..."
rm -f "$PROJECT_DIR"/*.deb

if (cd "$PROJECT_DIR" && fpm -s dir -t deb \
  -n "$PACKAGE_NAME" \
  -v "$NEW_VERSION" \
  --license "GPL-3.0-only AND CC-BY-SA-4.0" \
  --maintainer "$MAINTAINER" \
  --description "$DESCRIPTION" \
  --url "$URL" \
  --depends "python3-gi" \
  --depends "gir1.2-gtk-4.0" \
  --depends "python3-nautilus" \
  --after-install "$PROJECT_DIR/packaging/postinst" \
  -C "$BUILD_DIR" \
  usr/); then

  # --- Version recorded only after a fully successful build ---
  echo "$NEW_VERSION" > "$VERSION_FILE"
  echo ""
  echo "Package generated:"
  ls -1 "$PROJECT_DIR"/*.deb | sed 's/^/   /'
  echo "Version recorded: $NEW_VERSION (VERSION + Cargo.toml)"
else
  echo ""
  echo "Error: fpm failed."
  sed -i "s/^version = \".*\"/version = \"$CURRENT_VERSION\"/" "$CARGO_TOML"
  rm -rf "$BUILD_DIR"
  echo "Build cancelled: Cargo.toml restored."
  exit 1
fi
