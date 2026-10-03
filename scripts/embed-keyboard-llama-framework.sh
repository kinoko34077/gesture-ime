#!/bin/bash
set -euo pipefail

# AzooKeyKanaKanjiConverter 0.11.2 currently links llama.framework into the
# Keyboard Extension executable even when Zenzai traits are not enabled.
# Xcode/SwiftPM materializes the binary framework in BUILT_PRODUCTS_DIR but
# does not embed it into this app-extension target automatically.
#
# Because the extension Mach-O contains @rpath/llama.framework/llama, omitting
# the framework makes dyld terminate the extension before KeyboardViewController
# can run. Keep this copy step scoped to the extension until the upstream package
# graph no longer emits the strong runtime dependency.

SRC="${BUILT_PRODUCTS_DIR}/llama.framework"
DST_DIR="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
DST="${DST_DIR}/llama.framework"

if [[ ! -d "$SRC" ]]; then
  echo "Required llama.framework was not produced at: $SRC" >&2
  exit 70
fi

mkdir -p "$DST_DIR"
rm -rf "$DST"
/usr/bin/ditto "$SRC" "$DST"

# For normal signed Xcode builds, sign the nested framework with the same
# identity before the extension target itself is sealed. CI artifact builds
# disable signing and intentionally skip this branch.
if [[ "${CODE_SIGNING_ALLOWED:-NO}" == "YES" ]] \
   && [[ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]] \
   && [[ "${EXPANDED_CODE_SIGN_IDENTITY}" != "-" ]]; then
  /usr/bin/codesign \
    --force \
    --sign "${EXPANDED_CODE_SIGN_IDENTITY}" \
    --timestamp=none \
    "$DST"
fi

echo "Embedded llama.framework into Keyboard Extension: $DST"
