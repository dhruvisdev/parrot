#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
FINAL="$PWD/build/Parrot.app"
# Assemble a fresh bundle and swap it in: overwriting a running binary in place invalidates its
# code signature, and macOS kills it (a following `open` then fails with error -600).
APP="$PWD/build/Parrot.app.new"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Parrot "$APP/Contents/MacOS/Parrot"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
IDENTITY="${SIGNING_IDENTITY:--}"
# Notarization requires a secure timestamp; ad-hoc signatures cannot have one.
[[ $IDENTITY == - ]] && TIMESTAMP=() || TIMESTAMP=(--timestamp)
codesign --force --options runtime "${TIMESTAMP[@]}" --entitlements Resources/Parrot.entitlements --sign "$IDENTITY" "$APP"
if pgrep -xq Parrot; then
    pkill -x Parrot || true
    while pgrep -xq Parrot; do sleep 0.1; done
    echo "Quit the running Parrot"
fi
rm -rf "$FINAL"
mv "$APP" "$FINAL"
echo "Built $FINAL"
