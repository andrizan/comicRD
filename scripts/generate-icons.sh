#!/usr/bin/env bash
# Renders the desktop app icons (macOS, Linux, Windows) from the single SVG source.
# Requires: rsvg-convert (librsvg) and magick (ImageMagick).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/app_flutter"
SOURCE="$APP_DIR/assets/icon/comicrd_icon.svg"
MACOS_DIR="$APP_DIR/macos/Runner/Assets.xcassets/AppIcon.appiconset"
LINUX_PNG="$APP_DIR/linux/data/comicrd.png"
WINDOWS_ICO="$APP_DIR/windows/runner/resources/app_icon.ico"

for tool in rsvg-convert magick; do
  command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 1; }
done

render() {
  rsvg-convert -w "$1" -h "$1" "$SOURCE" -o "$2"
}

echo "==> macOS"
for size in 16 32 64 128 256 512 1024; do
  render "$size" "$MACOS_DIR/app_icon_${size}.png"
done

echo "==> Linux"
render 256 "$LINUX_PNG"

echo "==> Windows"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
ico_inputs=()
for size in 16 24 32 48 64 128 256; do
  render "$size" "$TMP_DIR/${size}.png"
  ico_inputs+=("$TMP_DIR/${size}.png")
done
magick "${ico_inputs[@]}" "$WINDOWS_ICO"

echo "Done."
