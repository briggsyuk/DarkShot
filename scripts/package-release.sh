#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION=release zsh scripts/build-app.sh
app="dist/DarkShot.app"
codesign --verify --deep --strict "$app"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
architecture="$(lipo -archs "$app/Contents/MacOS/DarkShot")"
case "$architecture" in
    arm64|x86_64) ;;
    *) architecture="universal" ;;
esac
release_directory="dist/releases/$version"
archive="DarkShot-$version-macOS-$architecture.zip"
mkdir -p "$release_directory"
ditto -c -k --sequesterRsrc --keepParent "$app" "$release_directory/$archive"
(
    cd "$release_directory"
    shasum -a 256 "$archive" > SHA256SUMS
)
echo "Release archive: $release_directory/$archive"
echo "Checksums: $release_directory/SHA256SUMS"
