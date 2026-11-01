#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
identifier="${1:-}"
scale="${2:-normal}"
mode="${3:-card}"
if [[ ! "$identifier" =~ ^[a-zA-Z0-9_-]{1,100}$ ]] || [[ "$scale" != normal && "$scale" != stress ]] || [[ "$mode" != card && "$mode" != main ]]; then
  echo "Usage: scripts/run-gui-benchmark.sh new-test-id [normal|stress] [card|main]" >&2; exit 2
fi
if /usr/bin/pgrep -f '/DailyToDo-Validation[.]app/Contents/MacOS/DailyToDo([[:space:]]|$)' >/dev/null; then
  echo "请先退出待办验收 App。" >&2; exit 3
fi
fixture_options=(--prepare-ui-fixture "$identifier")
if [[ "$scale" == stress ]]; then fixture_options+=(--stress); fi
swift run -c release TodoBenchmark "${fixture_options[@]}"
preview_app="$HOME/Applications/DailyToDo-Validation.app"
APP_OUTPUT="$preview_app" APP_BUNDLE_ID=local.tododesktop.validation APP_DISPLAY_NAME=待办验收 ./scripts/build-app.sh release
launch_options=("--ui-test=$identifier" --ui-performance)
if [[ "$mode" == card ]]; then launch_options+=(--ui-login); fi
echo "Keep the app idle for 8 seconds. Report: isolated test directory/gui-probe.json"
exec "$preview_app/Contents/MacOS/DailyToDo" "${launch_options[@]}"
