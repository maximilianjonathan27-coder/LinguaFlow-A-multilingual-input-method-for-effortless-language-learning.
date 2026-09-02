#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="LinguaFlowPrototype"
IME_NAME="LinguaFlow"
BUNDLE_ID="com.tianxq.LinguaFlowPrototype"
IME_BUNDLE_ID="com.tianxq.inputmethod.LinguaFlow"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/LinguaFlowPrototype.xcodeproj"
DERIVED_DATA="${LINGUAFLOW_DERIVED_DATA:-${TMPDIR:-/tmp}/LinguaFlowDerivedData}"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
IME_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$IME_NAME.app"
INSTALLED_APP="/Applications/$IME_NAME.app"
LEGACY_INSTALLED_APP="$HOME/Applications/$IME_NAME.app"
INSTALLED_IME="$HOME/Library/Input Methods/$IME_NAME.app"

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

discover_signing_identity() {
  if [[ -n "${LINGUAFLOW_CODE_SIGN_IDENTITY:-}" ]]; then
    printf '%s\n' "$LINGUAFLOW_CODE_SIGN_IDENTITY"
    return
  fi
  # Local development must not depend on a stale or revoked certificate still
  # present in Keychain. Distribution builds can opt in explicitly via the
  # environment variable above; ordinary builds use deterministic ad-hoc signing.
  printf '%s\n' "-"
}

SIGNING_IDENTITY="$(discover_signing_identity)"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  echo "Using ad-hoc local signing." >&2
fi

librime_library_path() {
  if [[ -n "${LINGUAFLOW_RIME_LIBRARY:-}" && -f "$LINGUAFLOW_RIME_LIBRARY" ]]; then
    printf '%s\n' "$LINGUAFLOW_RIME_LIBRARY"
    return 0
  fi
  local candidate
  for candidate in \
    /opt/homebrew/opt/librime/lib/librime.1.dylib \
    /usr/local/opt/librime/lib/librime.1.dylib; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

ensure_librime() {
  local library
  if library="$(librime_library_path)"; then
    echo "librime ready: $library"
    return
  fi

  if ! command -v brew >/dev/null 2>&1; then
    echo "LinguaFlow requires librime, but Homebrew is not installed." >&2
    echo "Install Homebrew from https://brew.sh, then run this command again." >&2
    return 1
  fi

  echo "librime is missing; installing it automatically with Homebrew..."
  HOMEBREW_NO_AUTO_UPDATE=1 brew install librime
  library="$(librime_library_path)" || {
    echo "Homebrew finished, but librime.1.dylib was not found." >&2
    return 1
  }
  echo "librime installed: $library"
}

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
    "$@"
}

build_app() {
  build_lexicon
  build_examples
  xcodebuild_common -scheme "$APP_NAME" build
}

build_ime() {
  ensure_librime
  build_lexicon
  build_examples
  xcodebuild_common -scheme LinguaFlowInputMethod build
}

verify_rime_runtime() {
  local probe user_data
  probe="$DERIVED_DATA/rime_bridge_probe"
  user_data="$DERIVED_DATA/RimeProbeUser"
  rm -rf "$user_data"
  mkdir -p "$user_data"

  xcrun clang \
    "$ROOT_DIR/script/rime_bridge_probe.c" \
    "$ROOT_DIR/LinguaFlowInputMethod/Rime/LFRimeBridge.c" \
    -I "$ROOT_DIR/LinguaFlowInputMethod/Rime" \
    -o "$probe"
  "$probe" \
    "$IME_BUNDLE/Contents/Resources/Rime" \
    "$user_data" \
    "wo'bu'zhi'd'z'm'z"
  rm -rf "$user_data"
  echo "librime runtime and mixed-Pinyin decoding are available."
}

test_app() {
  build_lexicon
  build_examples
  xcodebuild_common -scheme "$APP_NAME" test
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

build_examples() {
  python3 "$ROOT_DIR/script/build_examples.py" \
    "$ROOT_DIR/LexiconSource" \
    "$ROOT_DIR/LinguaFlowInputMethod/Resources/tatoeba_examples.sqlite"
  xattr -c "$ROOT_DIR/LinguaFlowInputMethod/Resources/tatoeba_examples.sqlite" || true
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

start_installed_ime() {
  /usr/bin/open -n "$INSTALLED_IME"
  for _ in {1..40}; do
    if pgrep -x "$IME_NAME" >/dev/null; then
      echo "$IME_NAME input method service is running."
      return 0
    fi
    sleep 0.25
  done

  echo "$IME_NAME was installed but its input method service did not start." >&2
  return 1
}

install_ime_from_build() {
  local previous_input_source="${1:-}"
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

  local lsregister
  lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  "$lsregister" -f -R -trusted "$INSTALLED_IME" >/dev/null 2>&1 || true
  xcrun swift "$ROOT_DIR/script/register_input_source.swift" "$INSTALLED_IME"
  start_installed_ime
  if [[ "$previous_input_source" == "$IME_BUNDLE_ID"* ]]; then
    xcrun swift "$ROOT_DIR/script/register_input_source.swift" --select "$previous_input_source"
  fi
  echo "Installed: $INSTALLED_IME"
  echo "The input method is registered and running. Switch away and back once if the current app cached the old input session."
}

install_preferences_app() {
  [[ -d "$APP_BUNDLE" ]] || { echo "Missing $APP_BUNDLE; build first." >&2; return 1; }

  local applications_dir staging backup
  applications_dir="$(dirname "$INSTALLED_APP")"
  staging="$applications_dir/.LinguaFlow.preferences.installing-$$.app"
  backup="$applications_dir/.LinguaFlow.preferences.backup-$$.app"

  mkdir -p "$applications_dir"
  rm -rf "$staging" "$backup"
  ditto "$APP_BUNDLE" "$staging"

  if [[ -d "$INSTALLED_APP" ]]; then
    mv "$INSTALLED_APP" "$backup"
  fi

  if ! mv "$staging" "$INSTALLED_APP"; then
    [[ -d "$backup" ]] && mv "$backup" "$INSTALLED_APP"
    return 1
  fi
  rm -rf "$backup"

  local lsregister
  lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

  if [[ -d "$LEGACY_INSTALLED_APP" && "$LEGACY_INSTALLED_APP" != "$INSTALLED_APP" ]]; then
    "$lsregister" -u "$LEGACY_INSTALLED_APP" >/dev/null 2>&1 || true
    rm -rf "$LEGACY_INSTALLED_APP"
  fi

  touch "$INSTALLED_APP"
  "$lsregister" -f -R -trusted "$INSTALLED_APP" >/dev/null 2>&1 || true
  killall Dock >/dev/null 2>&1 || true
  echo "Installed app: $INSTALLED_APP"
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
    previous_input_source="$(xcrun swift "$ROOT_DIR/script/register_input_source.swift" --current 2>/dev/null || true)"
    stop_processes
    ensure_librime
    build_app
    verify_rime_runtime
    install_preferences_app
    install_ime_from_build "$previous_input_source"
    ;;
  --verify-ime|verify-ime)
    build_ime
    verify_rime_runtime
    verify_ime
    ;;
  --build-lexicon|build-lexicon)
    build_lexicon
    build_examples
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
