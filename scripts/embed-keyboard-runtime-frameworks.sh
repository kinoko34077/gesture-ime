#!/bin/bash
set -euo pipefail

# AzooKeyKanaKanjiConverter 0.11.2 leaves a mandatory Mach-O dependency on
# @rpath/llama.framework/llama in the keyboard extension. Xcode/SPM links the
# binary target, but the generated project does not automatically embed the
# transitive binary framework in the .appex. Copy it before code signing.

if [[ "${PLATFORM_NAME:-}" != "iphoneos" ]]; then
  exit 0
fi

FRAMEWORK_NAME="llama.framework"
FRAMEWORK_BINARY="llama"
FRAMEWORKS_PATH="${FRAMEWORKS_FOLDER_PATH:-${WRAPPER_NAME}/Frameworks}"
DESTINATION_ROOT="${TARGET_BUILD_DIR:?}/${FRAMEWORKS_PATH}"
DESTINATION="${DESTINATION_ROOT}/${FRAMEWORK_NAME}"

SOURCE=""
CANDIDATES=(
  "${BUILT_PRODUCTS_DIR:-}/${FRAMEWORK_NAME}"
  "${BUILT_PRODUCTS_DIR:-}/PackageFrameworks/${FRAMEWORK_NAME}"
  "${BUILD_DIR:-}/${CONFIGURATION:-Release}${EFFECTIVE_PLATFORM_NAME:-}/${FRAMEWORK_NAME}"
  "${BUILD_DIR:-}/${CONFIGURATION:-Release}${EFFECTIVE_PLATFORM_NAME:-}/PackageFrameworks/${FRAMEWORK_NAME}"
)

for candidate in "${CANDIDATES[@]}"; do
  if [[ -d "$candidate" ]]; then
    SOURCE="$candidate"
    break
  fi
done

if [[ -z "$SOURCE" && -n "${BUILD_DIR:-}" ]]; then
  SOURCE="$(find "$BUILD_DIR" -type d -path "*/PackageFrameworks/${FRAMEWORK_NAME}" -print -quit 2>/dev/null || true)"
fi

if [[ -z "$SOURCE" || ! -d "$SOURCE" ]]; then
  echo "Required runtime framework not found: ${FRAMEWORK_NAME}" >&2
  echo "BUILT_PRODUCTS_DIR=${BUILT_PRODUCTS_DIR:-}" >&2
  echo "BUILD_DIR=${BUILD_DIR:-}" >&2
  exit 70
fi

mkdir -p "$DESTINATION_ROOT"
rm -rf "$DESTINATION"
ditto "$SOURCE" "$DESTINATION"

if [[ ! -f "$DESTINATION/${FRAMEWORK_BINARY}" ]]; then
  echo "Embedded framework binary missing: $DESTINATION/${FRAMEWORK_BINARY}" >&2
  exit 71
fi

if [[ "${CODE_SIGNING_ALLOWED:-NO}" == "YES" && -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
  /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$DESTINATION"
fi

echo "Embedded keyboard runtime framework: $DESTINATION"
