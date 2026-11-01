#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -ne 0 ]]; then
  echo "Usage: scripts/run-ui-tests.sh (optional DEVELOPER_DIR, UI_TEST_RESULTS_DIR, UI_TEST_DERIVED_DATA)" >&2; exit 2
fi
python3 scripts/generate-xcode-project.py --check
if ! xcrun --find xcodebuild >/dev/null 2>&1; then
  echo "需要完整 Xcode 16+；当前开发目录不包含 xcodebuild。未运行 UI 测试。可用 DEVELOPER_DIR 指向现有 Xcode，无需修改全局 xcode-select。" >&2
  exit 3
fi
if ! xcode_version="$(xcrun xcodebuild -version)"; then
  echo "无法读取 Xcode 版本；请先完成本机 Xcode 配置。未运行 UI 测试。" >&2; exit 3
fi
if [[ ! "$xcode_version" =~ ^Xcode[[:space:]]+([0-9]+) ]] || [[ "${BASH_REMATCH[1]:-0}" -lt 16 ]]; then
  echo "此工程需要 Xcode 16+ 与 Swift 6。未运行 UI 测试。" >&2; exit 3
fi
if /usr/bin/pgrep -f '/DailyToDoValidation[.]app/Contents/MacOS/DailyToDoValidation([[:space:]]|$)|/DailyToDoUITests-Runner[.]app/' >/dev/null; then
  echo "请先退出本次 Xcode 界面验收 App/Runner，再重建；未修改运行中的副本。" >&2; exit 3
fi
result_dir="${UI_TEST_RESULTS_DIR:-$PWD/build/ui-tests/$(date +%Y%m%d-%H%M%S)-$$}"
derived_data="${UI_TEST_DERIVED_DATA:-$PWD/build/XcodeDerivedData}"
mkdir -p "$result_dir"
if [[ -e "$result_dir/DailyToDo.xcresult" || -e "$result_dir/run.log" ]]; then
  echo "结果目录已存在，拒绝覆盖。请指定新的 UI_TEST_RESULTS_DIR。" >&2; exit 2
fi
echo "Only local.tododesktop.xcuitest is tested. Results: $result_dir/DailyToDo.xcresult"
xcrun xcodebuild -project DailyToDo.xcodeproj -scheme DailyToDo-UI -testPlan DailyToDo \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -derivedDataPath "$derived_data" -resultBundlePath "$result_dir/DailyToDo.xcresult" test 2>&1 | tee "$result_dir/run.log"
