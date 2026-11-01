#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Diagnostic functions, loaded ("sourced") by inside-fedora.sh.
# They use info() defined by the calling script and fill in
# MISSING_DEP with the packages that had to be added for GTK 4 to work.

GTK_CHECK='
import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk
v = (Gtk.get_major_version(), Gtk.get_minor_version(), Gtk.get_micro_version())
print("GTK %d.%d.%d" % v)
raise SystemExit(0 if v >= (4, 10, 0) else 1)'

# Names of the Fedora packages that provide the <namespace>-*.typelib file(s).
providers_of_typelib() {
    local ns="$1" names
    names=$(dnf repoquery --file "/usr/lib64/girepository-1.0/${ns}-*.typelib" \
            --queryformat '%{name}\n' 2>/dev/null | sort -u)
    if [ -z "$names" ]; then
        # Fallback: without an output format, the version is removed from the full name.
        names=$(dnf repoquery --file "/usr/lib64/girepository-1.0/${ns}-*.typelib" 2>/dev/null \
                | sed -E 's/-[0-9][^ ]*$//; s/^[0-9]+://' | sort -u)
    fi
    echo "$names" | grep -E '^[A-Za-z0-9_.+-]+$' | head -5
}

# diagnose_missing_typelib "<Python error message>"
# As long as the error says that an introspection file is missing (3 rounds at most),
# looks for the Fedora package that provides it, installs it and tests GTK again.
diagnose_missing_typelib() {
    local msg="$1" ns prev_ns="" candidates p round installed added=""
    for round in 1 2 3; do
        ns=$(echo "$msg" | grep -o "namespace '[A-Za-z0-9_]*'" | head -1 | sed "s/namespace '//; s/'//")
        if [ -z "$ns" ]; then
            info "diagnosis: the error does not point to a missing introspection file; nothing to try"
            return 0
        fi
        if [ "$ns" = "$prev_ns" ]; then
            info "diagnosis: \"$ns\" is still missing after the installation; stopping here"
            return 0
        fi
        prev_ns="$ns"
        info "diagnosis: introspection file \"$ns\" is missing; looking for the Fedora package that provides it"
        candidates=$(providers_of_typelib "$ns")
        if [ -z "$candidates" ]; then
            info "diagnosis: dnf found no provider; trying \"gobject-introspection\""
            candidates="gobject-introspection"
        else
            info "diagnosis: provider package(s): $(echo $candidates)"
        fi
        installed=""
        for p in $candidates; do
            if dnf -y install --setopt=install_weak_deps=False "$p" >/tmp/dnf-diag.log 2>&1; then
                installed="$p"
                added="${added:+$added }$p"
                if python3 -c "$GTK_CHECK" >/tmp/gtk-diag.log 2>&1; then
                    MISSING_DEP="$added"
                    info "diagnosis: with \"$added\" installed as well, GTK 4 works ($(tail -1 /tmp/gtk-diag.log))"
                    info "diagnosis: => these dependencies are missing from the .rpm package: $added"
                    return 0
                fi
                msg=$(tail -5 /tmp/gtk-diag.log)
                info "diagnosis: \"$p\" installed, but GTK does not work yet:"
                echo "$msg" | tail -2 | sed 's/^/      /'
                break
            else
                info "diagnosis: installing \"$p\" failed"
            fi
        done
        [ -n "$installed" ] || return 0
    done
    return 0
}
