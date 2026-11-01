#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
identifier="${1:-}"
if [[ ! "$identifier" =~ ^[a-zA-Z0-9_-]{1,100}$ ]]; then
  echo "Usage: scripts/run-ui-preview.sh test-id [--ui-stress] [--ui-dark|--ui-light] [--ui-login] [--ui-minimum-card] [--ui-open-reminder=task-UUID|countdown-UUID]" >&2
  exit 2
fi
shift
for option in "$@"; do
  case "$option" in
    --ui-stress|--ui-dark|--ui-light|--ui-login|--ui-minimum-card) ;;
    --ui-open-reminder=*)
      if [[ ! "$option" =~ ^--ui-open-reminder=(task|countdown)-[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        echo "Invalid reminder target; expected task-UUID or countdown-UUID." >&2; exit 2
      fi ;;
    *) echo "Unsupported preview option: $option" >&2; exit 2 ;;
  esac
done
# Never rebuild under a running executable or open the same test SQLite twice.
if /usr/bin/pgrep -f '/DailyToDo-Validation[.]app/Contents/MacOS/DailyToDo([[:space:]]|$)' >/dev/null; then
  echo "请先退出待办验收 App，再启动新的验收会话。" >&2
  exit 3
fi
preview_app="$HOME/Applications/DailyToDo-Validation.app"
APP_OUTPUT="$preview_app" APP_BUNDLE_ID=local.tododesktop.validation APP_DISPLAY_NAME=待办验收 ./scripts/build-app.sh debug
exec "$preview_app/Contents/MacOS/DailyToDo" "--ui-test=$identifier" --ui-demo "$@"
