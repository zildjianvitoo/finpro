#!/bin/bash
# Build finpro, install it on the booted simulator, open it on one screen, and save a small
# screenshot. One call instead of tapping through the flow.
#
#   ui-verify.sh [screen] [importFile]
#     screen      onboarding | vocalRange | home | importSong | recording   (default: home)
#     importFile  absolute path of an audio file; opens it in the Add a song screen (trimmer)
#
# Prints the screenshot path on the last line. Env: DEVICE (name, default "iPhone 17 Pro"),
# WIDTH (screenshot width in px, default 400), SKIP_BUILD=1 to reuse the last build.
set -euo pipefail

cd "$(dirname "$0")/../../.."
SCREEN="${1:-home}"
IMPORT_FILE="${2:-}"
DEVICE="${DEVICE:-iPhone 17 Pro}"
WIDTH="${WIDTH:-400}"
BUNDLE_ID="pakenanya.finpro"
OUT="${TMPDIR:-/tmp}/finpro-ui-verify"
mkdir -p "$OUT"

UDID="$(xcrun simctl list devices booted | grep -Eo '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}' | head -1 || true)"
if [ -z "$UDID" ]; then
  UDID="$(xcrun simctl list devices available | grep -F "$DEVICE (" | grep -Eo '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}' | head -1)"
  [ -n "$UDID" ] || { echo "No simulator named $DEVICE" >&2; exit 1; }
  xcrun simctl boot "$UDID"
fi
xcrun simctl bootstatus "$UDID" -b >/dev/null

DEST="id=$UDID"
if [ "${SKIP_BUILD:-0}" != "1" ]; then
  xcodebuild -project finpro.xcodeproj -scheme finpro -destination "$DEST" build 2>&1 \
    | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true
fi
PRODUCTS="$(xcodebuild -project finpro.xcodeproj -scheme finpro -destination "$DEST" -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/^ *BUILT_PRODUCTS_DIR/ {print $2; exit}')"

xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$PRODUCTS/finpro.app"
ARGS=(-startScreen "$SCREEN")
[ -n "$IMPORT_FILE" ] && ARGS+=(-importFile "$IMPORT_FILE")
xcrun simctl launch "$UDID" "$BUNDLE_ID" "${ARGS[@]}" >/dev/null
sleep 3

SHOT="$OUT/$SCREEN.png"
xcrun simctl io "$UDID" screenshot "$SHOT" >/dev/null 2>&1
sips --resampleWidth "$WIDTH" "$SHOT" >/dev/null
echo "$SHOT"
