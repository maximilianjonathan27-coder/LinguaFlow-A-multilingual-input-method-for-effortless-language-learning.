#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="LinguaFlowPrototype"
BUNDLE_ID="com.tianxq.LinguaFlowPrototype"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/LinguaFlowPrototype.xcodeproj"
DERIVED_DATA="$ROOT_DIR/.build/DerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

stop_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

build_app() {
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$APP_NAME" \
    -configuration Debug \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    build
}

test_app() {
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$APP_NAME" \
    -configuration Debug \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    test
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

verify_process() {
  for _ in {1..40}; do
    if pgrep -x "$APP_NAME" >/dev/null; then
      echo "$APP_NAME is running."
      return 0
    fi
    sleep 0.25
  done

  echo "$APP_NAME did not start within 10 seconds." >&2
  return 1
}

case "$MODE" in
  run)
    stop_app
    build_app
    open_app
    ;;
  --test|test)
    stop_app
    test_app
    ;;
  --verify|verify)
    stop_app
    build_app
    open_app
    verify_process
    ;;
  --debug|debug)
    stop_app
    build_app
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    stop_app
    build_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    stop_app
    build_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  *)
    echo "usage: $0 [run|--test|--verify|--debug|--logs|--telemetry]" >&2
    exit 2
    ;;
esac
