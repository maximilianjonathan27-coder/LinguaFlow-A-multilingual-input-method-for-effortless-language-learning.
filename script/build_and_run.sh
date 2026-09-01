#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="LinguaFlowPrototype"
IME_NAME="LinguaFlow"
BUNDLE_ID="com.tianxq.LinguaFlowPrototype"
IME_BUNDLE_ID="com.tianxq.inputmethod.LinguaFlow"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/LinguaFlowPrototype.xcodeproj"
DERIVED_DATA="${LINGUAFLOW_DERIVED_DATA:-$ROOT_DIR/.build/DerivedData}"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
IME_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$IME_NAME.app"
INSTALLED_IME="$HOME/Library/Input Methods/$IME_NAME.app"

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

discover_signing_identity() {
  if [[ -n "${LINGUAFLOW_CODE_SIGN_IDENTITY:-}" ]]; then
    printf '%s\n' "$LINGUAFLOW_CODE_SIGN_IDENTITY"
    return
  fi

  security find-identity -p codesigning -v 2>/dev/null \
    | awk '/Apple Development/ { print $2; exit }'
}

SIGNING_IDENTITY="$(discover_signing_identity)"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="-"
  echo "No Apple Development identity found; using ad-hoc local signing." >&2
fi

stop_processes() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  pkill -x "$IME_NAME" >/dev/null 2>&1 || true
}

xcodebuild_common() {
  xcodebuild \
    -project "$PROJECT_PATH" \
    -configuration Debug \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGNING_ALLOWED=NO \
    "$@"
}

build_app() {
  build_lexicon
  clear_signing_xattrs
  xcodebuild_common -scheme "$APP_NAME" build
  sign_bundle "$IME_BUNDLE"
  sign_bundle "$APP_BUNDLE"
}

build_ime() {
  build_lexicon
  clear_signing_xattrs
  xcodebuild_common -scheme LinguaFlowInputMethod build
  sign_bundle "$IME_BUNDLE"
}

test_app() {
  build_lexicon
  clear_signing_xattrs
  xcodebuild_common -scheme "$APP_NAME" test
}

clear_signing_xattrs() {
  xattr -cr "$ROOT_DIR/LinguaFlowInputMethod/Resources" || true
  xattr -c "$ROOT_DIR/LinguaFlowInputMethod/Info.plist" || true
  if [[ -d "$IME_BUNDLE" ]]; then
    xattr -cr "$IME_BUNDLE" || true
  fi
}

sign_bundle() {
  local bundle="$1"
  [[ -d "$bundle" ]] || return 0
  xattr -cr "$bundle" || true
  xattr -d com.apple.FinderInfo "$bundle" 2>/dev/null || true
  xattr -d 'com.apple.fileprovider.fpfs#P' "$bundle" 2>/dev/null || true
  codesign --force --deep --sign "$SIGNING_IDENTITY" "$bundle"
}

build_lexicon() {
  mkdir -p "$DERIVED_DATA/ModuleCache"
  CLANG_MODULE_CACHE_PATH="$DERIVED_DATA/ModuleCache" \
    SWIFT_MODULECACHE_PATH="$DERIVED_DATA/ModuleCache" \
    xcrun swift "$ROOT_DIR/script/build_lexicon.swift" \
      "$ROOT_DIR/LexiconSource" \
      "$ROOT_DIR/LinguaFlowInputMethod/Resources/linguaflow.sqlite"
  xattr -c "$ROOT_DIR/LinguaFlowInputMethod/Resources/linguaflow.sqlite" || true
}

open_setup_app() {
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

install_ime_from_build() {
  [[ -d "$IME_BUNDLE" ]] || { echo "Missing $IME_BUNDLE; build first." >&2; return 1; }

  local input_methods_dir staging backup
  input_methods_dir="$(dirname "$INSTALLED_IME")"
  staging="$input_methods_dir/.LinguaFlow.installing-$$.app"
  backup="$input_methods_dir/.LinguaFlow.backup-$$.app"

  mkdir -p "$input_methods_dir"
  rm -rf "$staging" "$backup"
  ditto "$IME_BUNDLE" "$staging"

  if [[ -d "$INSTALLED_IME" ]]; then
    mv "$INSTALLED_IME" "$backup"
  fi

  if ! mv "$staging" "$INSTALLED_IME"; then
    [[ -d "$backup" ]] && mv "$backup" "$INSTALLED_IME"
    return 1
  fi
  rm -rf "$backup"
  xattr -cr "$INSTALLED_IME" || true
  xattr -d com.apple.FinderInfo "$INSTALLED_IME" 2>/dev/null || true
  xattr -d 'com.apple.fileprovider.fpfs#P' "$INSTALLED_IME" 2>/dev/null || true

  # macOS may relaunch an active input method while the new bundle is still
  # building. Stop it again after the atomic replacement so the next launch
  # maps the newly installed executable instead of keeping the old image alive.
  pkill -x "$IME_NAME" >/dev/null 2>&1 || true

  local lsregister
  lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  "$lsregister" -f -R -trusted "$INSTALLED_IME" >/dev/null 2>&1 || true
  xcrun swift "$ROOT_DIR/script/register_input_source.swift" "$INSTALLED_IME"
  echo "Installed: $INSTALLED_IME"
  echo "Next: System Settings → Keyboard → Text Input → Edit → add LinguaFlow."
}

verify_ime() {
  [[ -d "$IME_BUNDLE" ]] || { echo "Built input method not found: $IME_BUNDLE" >&2; return 1; }
  plutil -lint "$IME_BUNDLE/Contents/Info.plist"
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$IME_BUNDLE/Contents/Info.plist")" == "$IME_BUNDLE_ID" ]]
  codesign --verify --deep --strict --verbose=2 "$IME_BUNDLE"
  echo "Input method bundle and signature are valid."

  if [[ -d "$INSTALLED_IME" ]]; then
    echo "Installed bundle: $INSTALLED_IME"
    xcrun swift "$ROOT_DIR/script/register_input_source.swift" --verify "$IME_BUNDLE_ID"
  else
    echo "Not installed yet: $INSTALLED_IME"
  fi
}

case "$MODE" in
  run)
    stop_processes
    build_app
    open_setup_app
    ;;
  --test|test)
    stop_processes
    test_app
    ;;
  --build-ime|build-ime)
    stop_processes
    build_ime
    ;;
  --install-ime|install-ime)
    stop_processes
    build_app
    install_ime_from_build
    ;;
  --verify-ime|verify-ime)
    build_ime
    verify_ime
    ;;
  --build-lexicon|build-lexicon)
    build_lexicon
    ;;
  --verify|verify)
    stop_processes
    build_app
    open_setup_app
    verify_process
    ;;
  --debug|debug)
    stop_processes
    build_app
    lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    ;;
  --logs|logs)
    stop_processes
    build_app
    open_setup_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    stop_processes
    build_app
    open_setup_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  *)
    echo "usage: $0 [run|--test|--build-lexicon|--build-ime|--install-ime|--verify-ime|--verify|--debug|--logs|--telemetry]" >&2
    exit 2
    ;;
esac
