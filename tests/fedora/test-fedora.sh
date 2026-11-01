#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Tests a .rpm package in a real Fedora (container), from your machine:
# installation with dnf (dependencies resolved by Fedora), package contents,
# engine, GTK 4, Nautilus extension with the real nautilus-python bindings,
# full GUI under Xvfb in the 4 languages, then uninstallation.
#
#   tests/fedora/test-fedora.sh [file.rpm] [fedora-version]
#
# Without a .rpm file, the script takes the one at the root of the repository
# (there must be only one). The Fedora version is "latest" by default;
# examples: 43, 44. podman (preferably) or docker is required: sudo apt install podman
#
# Run it BEFORE publishing a release, on the .rpm that is going to be published.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(dirname "$SCRIPT_DIR")"
ROOT_DIR="$(dirname "$TESTS_DIR")"

RPM="${1:-}"
VERSION="${2:-latest}"

if [ -z "$RPM" ]; then
    shopt -s nullglob
    found=("$ROOT_DIR"/*.rpm)
    shopt -u nullglob
    if [ "${#found[@]}" -eq 1 ]; then
        RPM="${found[0]}"
    else
        echo "Usage: $0 [file.rpm] [fedora-version]" >&2
        echo "${#found[@]} .rpm file(s) at the root of the repository: say which one as an argument." >&2
        exit 2
    fi
fi

if [ ! -f "$RPM" ]; then
    echo "File not found: '${RPM}'" >&2
    exit 2
fi

RUNTIME="$(command -v podman || command -v docker || true)"
if [ -z "$RUNTIME" ]; then
    echo "Neither podman nor docker is installed. Install podman with:" >&2
    echo "    sudo apt install podman" >&2
    exit 2
fi

RPM_DIR="$(cd "$(dirname "$RPM")" && pwd)"
RPM_NAME="$(basename "$RPM")"
IMAGE="registry.fedoraproject.org/fedora:${VERSION}"

echo "Container engine : $RUNTIME"
echo "Image            : $IMAGE (downloaded the first time, about 60 MB)"
echo "Package          : $RPM_DIR/$RPM_NAME"
echo "The package folder and the tests/ folder are mounted READ-ONLY in the container;"
echo "the container is deleted at the end. Nothing is installed on your machine."
echo

"$RUNTIME" run --rm \
    -v "$RPM_DIR":/pkg:ro \
    -v "$TESTS_DIR":/tests:ro \
    -e RPM_NAME="$RPM_NAME" \
    "$IMAGE" bash /tests/fedora/inside-fedora.sh
