#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

configuration="${CONFIGURATION:-release}"
swift build -c "$configuration"
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
app="dist/DarkShot.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/DarkShot" "$app/Contents/MacOS/DarkShot"
cp Resources/Info.plist "$app/Contents/Info.plist"
swift scripts/make-icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"

# Ad-hoc signing is for local use; macOS may require permission again after rebuilds.
# Set SIGN_IDENTITY to a Developer ID identity for distribution builds.
codesign --force --sign "${SIGN_IDENTITY:--}" --identifier com.darkshot.app "$app"
echo "Built $app"
