#!/bin/sh
# Builds a signed, notarized EdgeBar.app and publishes it as a GitHub release.
#   ./release.sh 1.0
#
# One-time setup: save notarization credentials under the name "edgebar":
#   xcrun notarytool store-credentials edgebar --apple-id <apple id> --team-id F65N98WT62
set -e
cd "$(dirname "$0")"

VERSION=${1:?usage: ./release.sh <version>, e.g. ./release.sh 1.0}
IDENTITY="Developer ID Application: Huijun Zhao (F65N98WT62)"
APP=build/EdgeBar.app
ZIP=build/EdgeBar-$VERSION.zip

# Build a universal app (Apple silicon + Intel).
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -target arm64-apple-macos26 Sources/EdgeBar.swift -o build/EdgeBar-arm64
swiftc -O -target x86_64-apple-macos26 Sources/EdgeBar.swift -o build/EdgeBar-x86_64
lipo -create build/EdgeBar-arm64 build/EdgeBar-x86_64 -output "$APP/Contents/MacOS/EdgeBar"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"

# Sign, notarize, staple.
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile edgebar --wait
xcrun stapler staple "$APP"
rm "$ZIP" && ditto -c -k --keepParent "$APP" "$ZIP"   # zip again, with the ticket inside
spctl -a -vv "$APP"

gh release create "v$VERSION" "$ZIP" --title "EdgeBar $VERSION" \
    --notes "Download **EdgeBar-$VERSION.zip**, unzip, drag EdgeBar.app to Applications, open it. Signed and notarized. macOS 26 or later."
