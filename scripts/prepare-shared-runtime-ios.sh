#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE="$ROOT/Shared/GestureIMECoreRust"
OUT="${SHARED_RUNTIME_IOS_DIR:-$ROOT/.build/GestureIMECoreSharedIOS}"
SOURCES="$OUT/Sources"
FFI="$OUT/FFI"
LIB="$OUT/Lib"

rm -rf "$OUT"
mkdir -p "$SOURCES" "$FFI" "$LIB"

pushd "$CORE" >/dev/null

# UniFFI metadata is read from a host library when generating Swift bindings.
cargo build

GEN="$OUT/generated"
mkdir -p "$GEN"
cargo run --bin uniffi-bindgen -- \
  target/debug/libgesture_ime_core.dylib \
  "$GEN" \
  --swift-sources \
  --headers \
  --modulemap \
  --module-name gesture_ime_coreFFI \
  --modulemap-filename gesture_ime_coreFFI.modulemap

find "$GEN" -maxdepth 1 -name '*.swift' -exec cp {} "$SOURCES/" \;
find "$GEN" -maxdepth 1 -name '*.h' -exec cp {} "$FFI/" \;
find "$GEN" -maxdepth 1 -name '*.modulemap' -exec cp {} "$FFI/" \;

MODULEMAP="$(find "$FFI" -maxdepth 1 -name '*.modulemap' -print -quit)"
if [[ -z "$MODULEMAP" ]]; then
  echo "UniFFI Swift modulemap missing" >&2
  exit 30
fi
cp "$MODULEMAP" "$FFI/module.modulemap"

if [[ -z "$(find "$SOURCES" -maxdepth 1 -name '*.swift' -print -quit)" ]]; then
  echo "UniFFI Swift source missing" >&2
  exit 31
fi

rustup target add aarch64-apple-ios
cargo build --release --target aarch64-apple-ios
cp target/aarch64-apple-ios/release/libgesture_ime_core.a "$LIB/"

popd >/dev/null

test -s "$LIB/libgesture_ime_core.a"
echo "Prepared shared iOS runtime at $OUT"
