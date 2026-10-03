#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="FreeTokenMonitor"
BUNDLE_ID="com.guodawei.FreeTokenMonitor"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_MACOS="$APP_BUNDLE/Contents/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"

case "$MODE" in
  run|--debug|--logs|--telemetry|--verify|--build-only|--preview|--render-preview|--render-live) ;;
  *) echo "usage: $0 [--build-only|--verify|--preview|--render-preview PNG_PATH|--render-live PNG_PATH|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac

if [[ "$MODE" != "--build-only" ]]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cat >"$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>Free Token Monitor</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
# Local ad-hoc signing; this is not a notarized distribution build.
/usr/bin/codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"

case "$MODE" in
  --build-only) ;;
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
  --verify)
    /usr/bin/open -n "$APP_BUNDLE"
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    echo "Free Token Monitor is running in the menu bar."
    ;;
  --preview) /usr/bin/open -n "$APP_BUNDLE" --args --preview ;;
  --render-preview|--render-live)
    [[ -n "${2:-}" ]] || { echo "A PNG destination is required." >&2; exit 2; }
    /usr/bin/open -n "$APP_BUNDLE" --args "$MODE" "$2"
    ;;
  --debug) lldb -- "$APP_BINARY" ;;
  --logs|--telemetry)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
esac
