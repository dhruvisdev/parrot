#!/bin/zsh
# Builds build/Parrot-<version>.dmg: signed with a Developer ID, notarized, and stapled.
#
# One-time setup:
#   xcrun notarytool store-credentials parrot-notary --apple-id <email> --team-id <TEAMID> --password <app-specific password>
# Release:
#   SIGNING_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" ./scripts/release.sh
# Local packaging test (ad-hoc, not notarized; Gatekeeper will block it on other Macs):
#   SIGNING_IDENTITY=- SKIP_NOTARIZE=1 ./scripts/release.sh
set -euo pipefail
cd "${0:A:h:h}"
: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to your Developer ID Application identity}"
NOTARY_PROFILE="${NOTARY_PROFILE:-parrot-notary}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
DMG="$PWD/build/Parrot-$VERSION.dmg"

./scripts/build-app.sh
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R build/Parrot.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Parrot $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
codesign --force --sign "$SIGNING_IDENTITY" "$DMG"

if [[ -z ${SKIP_NOTARIZE:-} ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature -v "$DMG"
fi
echo "Built $DMG"
