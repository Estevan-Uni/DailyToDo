#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
if [[ $# -gt 1 || ( "$configuration" != "release" && "$configuration" != "debug" ) ]]; then
  echo "Usage: scripts/build-app.sh [release|debug]" >&2
  exit 2
fi
destination="${APP_OUTPUT:-dist/DailyToDo.app}"
expected_id="${APP_BUNDLE_ID:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Resources/Info.plist)}"
python3 scripts/app-output-guard.py "$destination" "$expected_id"
swift build -c "$configuration" --product DailyToDo
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
# Sign outside Desktop/iCloud so Finder cannot reattach metadata mid-signature.
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/DailyToDo-build.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
app="$staging_dir/$(basename "$destination")"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" build/AppIcon.iconset
cp -X "$binary_dir/DailyToDo" "$app/Contents/MacOS/DailyToDo"
cp -X Resources/Info.plist "$app/Contents/Info.plist"
if [[ -n "${APP_BUNDLE_ID:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $APP_BUNDLE_ID" "$app/Contents/Info.plist"
fi
if [[ -n "${APP_DISPLAY_NAME:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_DISPLAY_NAME" "$app/Contents/Info.plist"
fi
swift scripts/make-icon.swift build/icon-1024.png
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" build/icon-1024.png --out "build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" build/icon-1024.png --out "build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
# Finder/Desktop metadata must not become part of the generated signed bundle.
xattr -cr "$app"
codesign --force --sign "${CODE_SIGN_IDENTITY:--}" --entitlements Resources/DailyToDo.entitlements "$app"
codesign --verify --deep --strict "$app"
plutil -lint "$app/Contents/Info.plist"
# Recheck after compilation/signing: the destination may have appeared or its
# App may have been opened while this build was in progress.
python3 scripts/app-output-guard.py "$destination" "$expected_id"
mkdir -p "$(dirname "$destination")"
ditto --noextattr --norsrc "$app" "$destination"
# ditto merges an existing bundle directory; remove its old root metadata too.
xattr -cr "$destination"
codesign --verify --deep --strict "$destination"
echo "Built: $destination"
