#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Exécuté À L'INTÉRIEUR du conteneur Fedora par test-fedora.sh.
# Ne pas le lancer directement sur votre machine : il installe des paquets.

set -u
KIT=/tests/fedora   # le dossier tests/ du dépôt, monté en lecture seule
RPM="/pkg/${RPM_NAME:?RPM_NAME non défini}"
PASS=0
FAIL=0
MISSING_DEP=""

ok()   { echo "  [OK]    $*"; PASS=$((PASS + 1)); }
ko()   { echo "  [ÉCHEC] $*"; FAIL=$((FAIL + 1)); }
info() { echo "  [info]  $*"; }
step() { echo; echo "=== $* ==="; }

# run "description" commande… : OK si le code de sortie est 0, sinon ÉCHEC
# avec la fin de la sortie de la commande.
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
        echo " DÉPENDANCE MANQUANTE AU PAQUET : $MISSING_DEP"
        echo " (les étapes suivantes ont tourné avec ce paquet installé en plus)"
    fi
    echo "=============================================="
    if [ "$FAIL" -eq 0 ]; then
        echo " RÉSULTAT : TOUT EST OK  ($PASS vérifications réussies, 0 échec)"
    else
        echo " RÉSULTAT : $FAIL ÉCHEC(S)  ($PASS vérifications réussies)"
    fi
    echo "=============================================="
    [ "$FAIL" -eq 0 ]
}

step "1. Système"
cat /etc/fedora-release
info "glibc : $(rpm -q glibc)"
info "paquet testé : $RPM_NAME"

step "2. Installation du paquet avec dnf (dépendances résolues par Fedora)"
if dnf -y install --setopt=install_weak_deps=False "$RPM" >/tmp/dnf-install.log 2>&1; then
    ok "dnf install a réussi"
else
    ko "dnf install a échoué"
    tail -30 /tmp/dnf-install.log | sed 's/^/      /'
    summary
    exit 1
fi
for pkg in nautilus-convert-images gtk4 nautilus-python python3-gobject; do
    if rpm -q "$pkg" >/dev/null 2>&1; then
        info "$(rpm -q "$pkg")"
    else
        ko "paquet $pkg non installé"
    fi
done

step "3. Contenu du paquet installé"
# Le conteneur Fedora peut refuser d'installer la documentation (« nodocs ») :
# on ignore donc les fichiers de documentation manquants.
bad=$(rpm -V nautilus-convert-images 2>&1 | grep -v -E '^missing +d ' || true)
if [ -z "$bad" ]; then
    ok "rpm -V : aucun écart avec le paquet"
else
    ko "rpm -V signale des écarts"
    echo "$bad" | sed 's/^/      /'
fi
for f in /usr/bin/convert-images-engine /usr/bin/convert-images-gui \
         /usr/share/nautilus-python/extensions/convert_images_nautilus.py \
         /usr/share/applications/nautilus-convert-images.desktop \
         /usr/share/locale/fr/LC_MESSAGES/nautilus-convert-images.mo \
         /usr/share/locale/es/LC_MESSAGES/nautilus-convert-images.mo \
         /usr/share/locale/de/LC_MESSAGES/nautilus-convert-images.mo; do
    if [ -e "$f" ]; then ok "présent : $f"; else ko "absent : $f"; fi
done

step "4. Moteur (programme Rust) sur ce Fedora"
run "convert-images-engine --version" convert-images-engine --version
info "$(convert-images-engine --version 2>&1)"
if ldd /usr/bin/convert-images-engine 2>&1 | grep -q 'not found'; then
    ko "bibliothèque manquante pour le moteur :"
    ldd /usr/bin/convert-images-engine | grep 'not found' | sed 's/^/      /'
else
    ok "toutes les bibliothèques du moteur sont présentes (ldd)"
fi
run "convert-images-engine formats" convert-images-engine formats

step "5. GTK 4 et PyGObject"
if gtk_out=$(python3 -c "$GTK_CHECK" 2>&1); then
    ok "GTK 4.10 ou plus récent est utilisable depuis Python (nécessaire à l'interface)"
    info "$gtk_out"
else
    ko "GTK 4 est inutilisable depuis Python : l'interface ne peut pas démarrer"
    echo "$gtk_out" | tail -3 | sed 's/^/      /'
    diagnose_missing_typelib "$gtk_out"
fi

step "6. Extension Nautilus avec les vraies liaisons de nautilus-python"
LANGUAGE=en run "entrée de menu en anglais" python3 "$KIT/helpers/check_extension.py" "Convert images…"
LANGUAGE=fr run "entrée de menu en français" python3 "$KIT/helpers/check_extension.py" "Convertir les images…"

step "7. Interface graphique complète (écran virtuel Xvfb), vrais fichiers, 4 langues"
if dnf -y install --setopt=install_weak_deps=False xorg-x11-server-Xvfb xorg-x11-xauth dejavu-sans-fonts >/tmp/dnf-xvfb.log 2>&1; then
    ok "outils d'écran virtuel installés (Xvfb)"
    for lang in en fr es de; do
        samples=$(mktemp -d)
        python3 "$KIT/helpers/make_samples.py" "$samples" >/dev/null
        # run_smoke.py imprime lui-même sa ligne [OK] ou [ÉCHEC] (avec le journal en cas d'échec).
        out=$(python3 "$KIT/helpers/run_smoke.py" "$lang" "$samples" 2>&1); rc=$?
        echo "$out" | grep -v -E 'libEGL|dbus-launch|^$'
        if [ $rc -eq 0 ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); fi
    done
else
    ko "impossible d'installer Xvfb : l'interface n'a pas pu être testée"
    tail -15 /tmp/dnf-xvfb.log | sed 's/^/      /'
fi

step "8. Désinstallation"
if dnf -y remove nautilus-convert-images >/tmp/dnf-remove.log 2>&1; then
    ok "dnf remove a réussi"
else
    ko "dnf remove a échoué"
    tail -15 /tmp/dnf-remove.log | sed 's/^/      /'
fi
for f in /usr/bin/convert-images-engine /usr/bin/convert-images-gui \
         /usr/share/nautilus-python/extensions/convert_images_nautilus.py; do
    if [ -e "$f" ]; then ko "toujours présent après désinstallation : $f"; else ok "supprimé : $f"; fi
done
if [ -d /usr/share/doc/nautilus-convert-images ]; then
    if [ -z "$(ls -A /usr/share/doc/nautilus-convert-images)" ]; then
        info "dossier vide laissé par le paquet (sans gravité) : /usr/share/doc/nautilus-convert-images"
    else
        ko "des fichiers restent après désinstallation : /usr/share/doc/nautilus-convert-images"
    fi
fi

summary
