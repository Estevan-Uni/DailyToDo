#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -gt 1 ]] || [[ -n "${1:-}" && "${1:-}" != "--install-local" ]]; then
  echo "Usage: scripts/package-app.sh [--install-local]" >&2; exit 2
fi
destination="$HOME/Applications/DailyToDo.app"
require_app_closed() {
  python3 scripts/app-output-guard.py "$destination" local.tododesktop.mac
  # Both names use the same sandbox/data. Never install over a live legacy App.
  if [[ -e "$HOME/Applications/TodoDesktop.app" ]]; then
    python3 scripts/app-output-guard.py "$HOME/Applications/TodoDesktop.app" local.tododesktop.mac
  fi
}
if [[ "${1:-}" == "--install-local" ]]; then require_app_closed; fi
package_dir="$(mktemp -d "${TMPDIR:-/tmp}/DailyToDo-package.XXXXXX")"
trap 'rm -rf "$package_dir"' EXIT
APP_OUTPUT="$package_dir/DailyToDo.app" ./scripts/build-app.sh release
mkdir -p dist
archive="dist/DailyToDo-macOS-arm64-preview.zip"
pending_archive="$package_dir/DailyToDo-macOS-arm64-preview.zip"
ditto -c -k --norsrc --noextattr --keepParent "$package_dir/DailyToDo.app" "$pending_archive"
mkdir -p "$package_dir/verify"
ditto -x -k "$pending_archive" "$package_dir/verify"
codesign --verify --deep --strict "$package_dir/verify/DailyToDo.app"
mv "$pending_archive" "$archive"
shasum -a 256 "$archive" > "$archive.sha256"
echo "Packaged and extraction verified: $archive"
if [[ "${1:-}" == "--install-local" ]]; then
  # The app may have been opened while the Release bundle was being built.
  require_app_closed
  mkdir -p "$HOME/Applications"
  ditto --norsrc --noextattr "$package_dir/DailyToDo.app" "$destination"
  xattr -cr "$destination"
  codesign --verify --deep --strict "$destination"
  echo "Installed: $destination"
fi
