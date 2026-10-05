#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required" >&2
  exit 2
fi

DERIVED_DATA="${DERIVED_DATA:-$RUNNER_TEMP/GestureIMEKeyboardDerivedData}"
ARTIFACT_DIR="${ARTIFACT_DIR:-$RUNNER_TEMP/GestureIMEKeyboardArtifact}"

rm -rf "$DERIVED_DATA" "$ARTIFACT_DIR" GestureIME.xcodeproj
mkdir -p "$ARTIFACT_DIR"

bash scripts/prepare-shared-runtime-ios.sh
xcodegen generate --spec project.yml

APP_GROUP_ID="group.net.kinotch.gestureime"
APP_ENTITLEMENT_GROUP="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' App/GestureIMEApp.entitlements)"
KEYBOARD_ENTITLEMENT_GROUP="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' App/GestureKeyboard.entitlements)"
if [[ "$APP_ENTITLEMENT_GROUP" != "$APP_GROUP_ID" || "$KEYBOARD_ENTITLEMENT_GROUP" != "$APP_GROUP_ID" ]]; then
  echo "App Group entitlement mismatch: app=$APP_ENTITLEMENT_GROUP keyboard=$KEYBOARD_ENTITLEMENT_GROUP expected=$APP_GROUP_ID" >&2
  exit 9
fi

SOURCE_OPEN_ACCESS="$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionAttributes:RequestsOpenAccess' App/KeyboardExtension/Info.plist)"
if [[ "$SOURCE_OPEN_ACCESS" != "false" ]]; then
  echo "Keyboard must keep RequestsOpenAccess=false; got $SOURCE_OPEN_ACCESS" >&2
  exit 10
fi

xcodebuild \
  -project GestureIME.xcodeproj \
  -scheme GestureIME \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP_PATH="$DERIVED_DATA/Build/Products/Release-iphoneos/GestureIME.app"
APPEX_PATH="$APP_PATH/PlugIns/GestureKeyboard.appex"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app bundle missing: $APP_PATH" >&2
  exit 3
fi

if [[ ! -d "$APPEX_PATH" ]]; then
  echo "Expected keyboard extension missing: $APPEX_PATH" >&2
  find "$APP_PATH" -maxdepth 4 -print
  exit 4
fi

EXTENSION_POINT="$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$APPEX_PATH/Info.plist")"
if [[ "$EXTENSION_POINT" != "com.apple.keyboard-service" ]]; then
  echo "Unexpected extension point: $EXTENSION_POINT" >&2
  exit 5
fi

APP_INFO_GROUP="$(/usr/libexec/PlistBuddy -c 'Print :GestureIMEAppGroupIdentifier' "$APP_PATH/Info.plist")"
KEYBOARD_INFO_GROUP="$(/usr/libexec/PlistBuddy -c 'Print :GestureIMEAppGroupIdentifier' "$APPEX_PATH/Info.plist")"
BUILT_OPEN_ACCESS="$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionAttributes:RequestsOpenAccess' "$APPEX_PATH/Info.plist")"
if [[ "$APP_INFO_GROUP" != "$APP_GROUP_ID" || "$KEYBOARD_INFO_GROUP" != "$APP_GROUP_ID" ]]; then
  echo "Built Info.plist App Group mismatch: app=$APP_INFO_GROUP keyboard=$KEYBOARD_INFO_GROUP expected=$APP_GROUP_ID" >&2
  exit 11
fi
if [[ "$BUILT_OPEN_ACCESS" != "false" ]]; then
  echo "Built keyboard unexpectedly requests Full Access: $BUILT_OPEN_ACCESS" >&2
  exit 12
fi

if [[ ! -f "$APPEX_PATH/default-ja.json" ]]; then
  echo "Built-in profile resource missing from keyboard extension" >&2
  find "$APPEX_PATH" -maxdepth 2 -print
  exit 6
fi

KEYBOARD_BINARY="$APPEX_PATH/GestureKeyboard"
if [[ ! -f "$KEYBOARD_BINARY" ]]; then
  echo "Keyboard extension executable missing: $KEYBOARD_BINARY" >&2
  exit 7
fi

if /usr/bin/otool -L "$KEYBOARD_BINARY" | grep -Fq "@rpath/llama.framework/llama"; then
  LLAMA_BINARY="$APPEX_PATH/Frameworks/llama.framework/llama"
  if [[ ! -f "$LLAMA_BINARY" ]]; then
    echo "Keyboard executable requires llama.framework but it is not embedded" >&2
    /usr/bin/otool -L "$KEYBOARD_BINARY" >&2
    find "$APPEX_PATH" -maxdepth 3 -print >&2
    exit 8
  fi
fi

mkdir -p "$ARTIFACT_DIR/Payload"
ditto "$APP_PATH" "$ARTIFACT_DIR/Payload/GestureIME.app"
(
  cd "$ARTIFACT_DIR"
  /usr/bin/zip -qry GestureIME-keyboard-unsigned.ipa Payload
)

echo "Containing app:"
plutil -p "$APP_PATH/Info.plist"

echo "Keyboard extension:"
plutil -p "$APPEX_PATH/Info.plist"

echo "IPA: $ARTIFACT_DIR/GestureIME-keyboard-unsigned.ipa"
