#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Fonctions de diagnostic, chargées (« source ») par inside-fedora.sh.
# Elles utilisent info() définie par le script appelant et renseignent
# MISSING_DEP avec les paquets qu'il a fallu ajouter pour que GTK 4 fonctionne.

GTK_CHECK='
import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk
v = (Gtk.get_major_version(), Gtk.get_minor_version(), Gtk.get_micro_version())
print("GTK %d.%d.%d" % v)
raise SystemExit(0 if v >= (4, 10, 0) else 1)'

# Noms des paquets Fedora qui fournissent le(s) fichier(s) <espace-de-noms>-*.typelib.
providers_of_typelib() {
    local ns="$1" names
    names=$(dnf repoquery --file "/usr/lib64/girepository-1.0/${ns}-*.typelib" \
            --queryformat '%{name}\n' 2>/dev/null | sort -u)
    if [ -z "$names" ]; then
        # Repli : sans format de sortie, on retire la version du nom complet.
        names=$(dnf repoquery --file "/usr/lib64/girepository-1.0/${ns}-*.typelib" 2>/dev/null \
                | sed -E 's/-[0-9][^ ]*$//; s/^[0-9]+://' | sort -u)
    fi
    echo "$names" | grep -E '^[A-Za-z0-9_.+-]+$' | head -5
}

# diagnose_missing_typelib "<message d'erreur Python>"
# Tant que l'erreur dit qu'un fichier d'introspection manque (3 tours au plus),
# cherche quel paquet Fedora le fournit, l'installe et reteste GTK.
diagnose_missing_typelib() {
    local msg="$1" ns prev_ns="" candidates p round installed added=""
    for round in 1 2 3; do
        ns=$(echo "$msg" | grep -o "namespace '[A-Za-z0-9_]*'" | head -1 | sed "s/namespace '//; s/'//")
        if [ -z "$ns" ]; then
            info "diagnostic : l'erreur ne désigne pas un fichier d'introspection manquant ; rien à tenter"
            return 0
        fi
        if [ "$ns" = "$prev_ns" ]; then
            info "diagnostic : « $ns » manque toujours après l'installation ; on s'arrête là"
            return 0
        fi
        prev_ns="$ns"
        info "diagnostic : il manque le fichier d'introspection « $ns » ; recherche du paquet Fedora qui le fournit"
        candidates=$(providers_of_typelib "$ns")
        if [ -z "$candidates" ]; then
            info "diagnostic : dnf n'a trouvé aucun fournisseur ; essai de « gobject-introspection »"
            candidates="gobject-introspection"
        else
            info "diagnostic : paquet(s) fournisseur(s) : $(echo $candidates)"
        fi
        installed=""
        for p in $candidates; do
            if dnf -y install --setopt=install_weak_deps=False "$p" >/tmp/dnf-diag.log 2>&1; then
                installed="$p"
                added="${added:+$added }$p"
                if python3 -c "$GTK_CHECK" >/tmp/gtk-diag.log 2>&1; then
                    MISSING_DEP="$added"
                    info "diagnostic : en installant « $added » en plus, GTK 4 fonctionne ($(tail -1 /tmp/gtk-diag.log))"
                    info "diagnostic : => il manque ces dépendances au paquet .rpm : $added"
                    return 0
                fi
                msg=$(tail -5 /tmp/gtk-diag.log)
                info "diagnostic : « $p » installé, mais GTK ne fonctionne pas encore :"
                echo "$msg" | tail -2 | sed 's/^/      /'
                break
            else
                info "diagnostic : l'installation de « $p » a échoué"
            fi
        done
        [ -n "$installed" ] || return 0
    done
    return 0
}
