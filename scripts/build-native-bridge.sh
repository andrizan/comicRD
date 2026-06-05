#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM=""
CONFIGURATION=""
DESTINATION=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --platform)
      PLATFORM="${2:-}"
      shift 2
      ;;
    --configuration)
      CONFIGURATION="${2:-}"
      shift 2
      ;;
    --destination)
      DESTINATION="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "$PLATFORM" ] || [ -z "$CONFIGURATION" ] || [ -z "$DESTINATION" ]; then
  echo "Usage: build-native-bridge.sh --platform <linux|macos> --configuration <Debug|Profile|Release> --destination <dir>" >&2
  exit 1
fi

case "$CONFIGURATION" in
  Profile|Release)
    PROFILE="release"
    CARGO_PROFILE_ARGS=(--release)
    ;;
  *)
    PROFILE="debug"
    CARGO_PROFILE_ARGS=()
    ;;
esac

case "$PLATFORM" in
  linux)
    LIBRARY_NAME="libcomicrd_bridge.so"
    ;;
  macos)
    LIBRARY_NAME="libcomicrd_bridge.dylib"
    ;;
  *)
    echo "Unsupported platform for shell script: $PLATFORM" >&2
    exit 1
    ;;
esac

(
  cd "$ROOT_DIR"
  cargo build -p comicrd_bridge "${CARGO_PROFILE_ARGS[@]}"
)

ARTIFACT="$ROOT_DIR/target/$PROFILE/$LIBRARY_NAME"
if [ ! -f "$ARTIFACT" ]; then
  echo "Expected native bridge artifact was not found: $ARTIFACT" >&2
  exit 1
fi

mkdir -p "$DESTINATION"
cp "$ARTIFACT" "$DESTINATION/$LIBRARY_NAME"

echo "Bundled $LIBRARY_NAME from target/$PROFILE to $DESTINATION"
