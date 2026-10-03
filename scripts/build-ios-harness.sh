#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required" >&2
  exit 2
fi

DERIVED_DATA="${DERIVED_DATA:-$RUNNER_TEMP/GestureHarnessDerivedData}"
ARTIFACT_DIR="${ARTIFACT_DIR:-$RUNNER_TEMP/GestureHarnessArtifact}"

rm -rf "$DERIVED_DATA" "$ARTIFACT_DIR" GestureIME.xcodeproj
mkdir -p "$ARTIFACT_DIR"

xcodegen generate --spec project.yml

xcodebuild \
  -project GestureIME.xcodeproj \
  -scheme GestureHarness \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP_PATH="$DERIVED_DATA/Build/Products/Release-iphoneos/GestureHarness.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app bundle missing: $APP_PATH" >&2
  find "$DERIVED_DATA/Build/Products" -maxdepth 3 -type d -name '*.app' -print || true
  exit 3
fi

mkdir -p "$ARTIFACT_DIR/Payload"
ditto "$APP_PATH" "$ARTIFACT_DIR/Payload/GestureHarness.app"

(
  cd "$ARTIFACT_DIR"
  /usr/bin/zip -qry GestureHarness-unsigned.ipa Payload
)

plutil -p "$APP_PATH/Info.plist"
echo "IPA: $ARTIFACT_DIR/GestureHarness-unsigned.ipa"
