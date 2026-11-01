#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Updates the template (.pot) from the code, then merges the new texts into
# each language catalog (po/*.po). For maintainers only:
# requires the GNU gettext tools (xgettext, msgmerge, msgfmt).
#   Debian/Ubuntu : sudo apt install gettext      Fedora : sudo dnf install gettext
set -euo pipefail
cd "$(dirname "$0")/.."

for tool in xgettext msgmerge msgfmt; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Error: '$tool' not found (gettext package)." >&2; exit 1; }
done

DOMAIN="nautilus-convert-images"
POT="po/$DOMAIN.pot"

xgettext --language=Python --from-code=UTF-8 \
  --keyword=_ --keyword=N_ --keyword=ngettext:1,2 --add-comments=TRANSLATORS \
  --package-name="$DOMAIN" \
  --msgid-bugs-address="https://github.com/gillesmagneville/nautilus-convert-images/issues" \
  --copyright-holder="Gilles MAGNEVILLE" --sort-by-file \
  -o "$POT" \
  nautilus-extension/convert-images-gui nautilus-extension/convert_images_nautilus.py

for po in po/*.po; do
  [ -f "$po" ] || continue
  msgmerge --update --backup=none --no-fuzzy-matching --quiet "$po" "$POT"
  printf '%s : ' "$po"
  msgfmt --check --statistics -o /dev/null "$po"
done
echo "Done. Review the entries marked \"fuzzy\" or empty before committing."
