#!/bin/zsh
# Regenerates Resources/AppIcon.icns from the shared mark in Sources/Parrot/Mark.swift.
set -euo pipefail
cd "${0:A:h:h}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
swiftc -O -o "$WORK/icon" scripts/icon/main.swift Sources/Parrot/Mark.swift
"$WORK/icon" "$WORK/AppIcon.iconset"
iconutil -c icns -o Resources/AppIcon.icns "$WORK/AppIcon.iconset"
[[ -n ${ICON_PREVIEW:-} ]] && cp "$WORK/AppIcon.iconset/icon_512x512@2x.png" "$ICON_PREVIEW"
echo "Wrote Resources/AppIcon.icns"
