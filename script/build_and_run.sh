#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Arclume"
PROCESS_NAME="Arclume"
DISPLAY_NAME="Arclume"
BUNDLE_ID="io.github.pigeonmuyz.arclume"
PROJECT_NAME="Arclume.xcodeproj"
SCHEME="Arclume"
CONFIGURATION="${CONFIGURATION:-Debug}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/$PROJECT_NAME"
DERIVED_DATA_PATH="$ROOT_DIR/DerivedData"
APP_BUNDLE="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
CONFIG_FILE="$ROOT_DIR/Arclume/Config.xcconfig"

usage() {
  echo "usage: $0 [run|debug|logs|telemetry|verify]" >&2
}

case "$MODE" in
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify)
    ;;
  *)
    usage
    exit 2
    ;;
esac

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing $CONFIG_FILE. Create the local API build configuration before running $DISPLAY_NAME." >&2
  exit 1
fi

pkill -x "$PROCESS_NAME" >/dev/null 2>&1 || true

# Keep the project's Apple Development identity across local replacements so
# macOS privacy grants can follow the app's designated requirement. Ad-hoc
# signing binds grants to a changing code hash and is only an explicit opt-in.
SIGNING_ARGS=("SWIFT_EMIT_LOC_STRINGS=NO")
if [[ -n "${ARCLUME_CODE_SIGN_IDENTITY:-}" ]]; then
  SIGNING_ARGS+=("CODE_SIGN_IDENTITY=$ARCLUME_CODE_SIGN_IDENTITY" "CODE_SIGN_STYLE=Manual")
  if [[ "$ARCLUME_CODE_SIGN_IDENTITY" == "-" ]]; then
    SIGNING_ARGS+=("DEVELOPMENT_TEAM=")
    echo "警告：临时签名可能使每次重新构建后需要重新授权麦克风。" >&2
  fi
fi

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  "${SIGNING_ARGS[@]}" \
  build

if [[ ! -d "$APP_BUNDLE" || ! -x "$APP_BINARY" ]]; then
  echo "$DISPLAY_NAME build product was not found at $APP_BUNDLE" >&2
  exit 1
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    for _ in {1..20}; do
      if pgrep -x "$PROCESS_NAME" >/dev/null; then
        echo "$DISPLAY_NAME is running."
        exit 0
      fi
      sleep 0.25
    done
    echo "$DISPLAY_NAME did not start within 5 seconds." >&2
    exit 1
    ;;
esac
