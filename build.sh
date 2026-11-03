#!/bin/sh
# Builds build/EdgeBar.app. With "install", also copies it to /Applications and opens it.
#   ./build.sh            build only
#   ./build.sh install    build, install, launch
set -e
cd "$(dirname "$0")"

APP=build/EdgeBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O Sources/EdgeBar.swift -o "$APP/Contents/MacOS/EdgeBar"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"     # ad-hoc signature, so macOS will run it
echo "Built $APP"

if [ "$1" = "install" ]; then
    pkill -x EdgeBar 2>/dev/null || true
    rm -rf /Applications/EdgeBar.app
    cp -R "$APP" /Applications/
    open /Applications/EdgeBar.app
    echo "Installed /Applications/EdgeBar.app"
fi
