#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Run INSIDE the Fedora container by test-fedora.sh.
# Do not run it directly on your machine: it installs packages.

set -u
KIT=/tests/fedora   # the repository's tests/ folder, mounted read-only
RPM="/pkg/${RPM_NAME:?RPM_NAME is not set}"
PASS=0
FAIL=0
MISSING_DEP=""

ok()   { echo "  [OK]    $*"; PASS=$((PASS + 1)); }
ko()   { echo "  [FAIL]  $*"; FAIL=$((FAIL + 1)); }
info() { echo "  [info]  $*"; }
step() { echo; echo "=== $* ==="; }

# run "description" command...: OK if the exit code is 0, otherwise FAIL
# with the tail of the command's output.
run() {
    local desc="$1"; shift
    local out rc
    out=$("$@" 2>&1); rc=$?
    if [ $rc -eq 0 ]; then
        ok "$desc"
    else
        ko "$desc (code $rc)"
        echo "$out" | tail -25 | sed 's/^/      /'
    fi
    return $rc
}

# shellcheck source=helpers/diagnose.sh
. "$KIT/helpers/diagnose.sh"

summary() {
    echo
    if [ -n "$MISSING_DEP" ]; then
        echo " MISSING DEPENDENCY IN THE PACKAGE: $MISSING_DEP"
        echo " (the following steps ran with this package installed in addition)"
    fi
    echo "=============================================="
    if [ "$FAIL" -eq 0 ]; then
        echo " RESULT: EVERYTHING IS OK  ($PASS checks passed, 0 failures)"
    else
        echo " RESULT: $FAIL FAILURE(S)  ($PASS checks passed)"
    fi
    echo "=============================================="
    [ "$FAIL" -eq 0 ]
}

step "1. System"
cat /etc/fedora-release
info "glibc: $(rpm -q glibc)"
info "package tested: $RPM_NAME"

step "2. Installing the package with dnf (dependencies resolved by Fedora)"
if dnf -y install --setopt=install_weak_deps=False "$RPM" >/tmp/dnf-install.log 2>&1; then
    ok "dnf install succeeded"
else
    ko "dnf install failed"
    tail -30 /tmp/dnf-install.log | sed 's/^/      /'
    summary
    exit 1
fi
for pkg in nautilus-convert-images gtk4 nautilus-python python3-gobject; do
    if rpm -q "$pkg" >/dev/null 2>&1; then
        info "$(rpm -q "$pkg")"
    else
        ko "package $pkg not installed"
    fi
done

step "3. Contents of the installed package"
# The Fedora container may refuse to install the documentation ("nodocs"):
# missing documentation files are therefore ignored.
bad=$(rpm -V nautilus-convert-images 2>&1 | grep -v -E '^missing +d ' || true)
if [ -z "$bad" ]; then
    ok "rpm -V: no difference from the package"
else
    ko "rpm -V reports differences"
    echo "$bad" | sed 's/^/      /'
fi
for f in /usr/bin/convert-images-engine /usr/bin/convert-images-gui \
         /usr/share/nautilus-python/extensions/convert_images_nautilus.py \
         /usr/share/applications/nautilus-convert-images.desktop \
         /usr/share/locale/fr/LC_MESSAGES/nautilus-convert-images.mo \
         /usr/share/locale/es/LC_MESSAGES/nautilus-convert-images.mo \
         /usr/share/locale/de/LC_MESSAGES/nautilus-convert-images.mo; do
    if [ -e "$f" ]; then ok "present: $f"; else ko "missing: $f"; fi
done

step "4. Engine (Rust program) on this Fedora"
run "convert-images-engine --version" convert-images-engine --version
info "$(convert-images-engine --version 2>&1)"
if ldd /usr/bin/convert-images-engine 2>&1 | grep -q 'not found'; then
    ko "missing library for the engine:"
    ldd /usr/bin/convert-images-engine | grep 'not found' | sed 's/^/      /'
else
    ok "all the engine's libraries are present (ldd)"
fi
run "convert-images-engine formats" convert-images-engine formats

step "5. GTK 4 and PyGObject"
if gtk_out=$(python3 -c "$GTK_CHECK" 2>&1); then
    ok "GTK 4.10 or newer is usable from Python (needed by the GUI)"
    info "$gtk_out"
else
    ko "GTK 4 is unusable from Python: the GUI cannot start"
    echo "$gtk_out" | tail -3 | sed 's/^/      /'
    diagnose_missing_typelib "$gtk_out"
fi

step "6. Nautilus extension with the real nautilus-python bindings"
LANGUAGE=en run "menu entry in English" python3 "$KIT/helpers/check_extension.py" "Convert images…"
LANGUAGE=fr run "menu entry in French" python3 "$KIT/helpers/check_extension.py" "Convertir les images…"

step "7. Full GUI (virtual Xvfb screen), real files, 4 languages"
if dnf -y install --setopt=install_weak_deps=False xorg-x11-server-Xvfb xorg-x11-xauth dejavu-sans-fonts >/tmp/dnf-xvfb.log 2>&1; then
    ok "virtual screen tools installed (Xvfb)"
    for lang in en fr es de; do
        samples=$(mktemp -d)
        python3 "$KIT/helpers/make_samples.py" "$samples" >/dev/null
        # run_smoke.py prints its own [OK] or [FAIL] line (with the log on failure).
        out=$(python3 "$KIT/helpers/run_smoke.py" "$lang" "$samples" 2>&1); rc=$?
        echo "$out" | grep -v -E 'libEGL|dbus-launch|^$'
        if [ $rc -eq 0 ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); fi
    done
else
    ko "could not install Xvfb: the GUI could not be tested"
    tail -15 /tmp/dnf-xvfb.log | sed 's/^/      /'
fi

step "8. Uninstallation"
if dnf -y remove nautilus-convert-images >/tmp/dnf-remove.log 2>&1; then
    ok "dnf remove succeeded"
else
    ko "dnf remove failed"
    tail -15 /tmp/dnf-remove.log | sed 's/^/      /'
fi
for f in /usr/bin/convert-images-engine /usr/bin/convert-images-gui \
         /usr/share/nautilus-python/extensions/convert_images_nautilus.py; do
    if [ -e "$f" ]; then ko "still present after uninstallation: $f"; else ok "removed: $f"; fi
done
if [ -d /usr/share/doc/nautilus-convert-images ]; then
    if [ -z "$(ls -A /usr/share/doc/nautilus-convert-images)" ]; then
        info "empty folder left by the package (harmless): /usr/share/doc/nautilus-convert-images"
    else
        ko "files remain after uninstallation: /usr/share/doc/nautilus-convert-images"
    fi
fi

summary
