#!/usr/bin/env bash
# package.sh — build Merken.app and wrap it in a drag-install DMG.
#
# Usage:  ./package.sh [version]
# e.g.    ./package.sh 0.2.0   →   Merken-0.2.0.dmg
set -euo pipefail

VERSION="${1:-0.2.0}"
APP="Merken.app"
DMG="Merken-${VERSION}.dmg"

cd "$(dirname "$0")"

echo "▸ Building Merken.app…"
./build.sh > /dev/null

if [[ ! -d "$APP" ]]; then
    echo "✗ $APP not found after build" >&2
    exit 1
fi

STAGING=$(mktemp -d -t merken-pkg)
trap 'rm -rf "$STAGING"' EXIT

echo "▸ Staging contents in $STAGING…"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

cat > "$STAGING/README.txt" <<EOF
Merken ${VERSION}

To install:
  Drag Merken.app onto the Applications shortcut.

On first launch Merken will:
  · ask you to pick a vault folder
  · check for Ollama (and send you to install it if missing)
  · let you pick a model — the recommended one fits 16 GB Macs
  · download the model in the background, no terminal needed

Source & issues:  https://github.com/JulianWohlleber/CL-Merken
EOF

echo "▸ Building $DMG…"
rm -f "$DMG"
hdiutil create \
    -volname "Merken ${VERSION}" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG" > /dev/null

SIZE=$(du -h "$DMG" | cut -f1 | tr -d ' ')
echo "✓ Built $DMG (${SIZE})"
