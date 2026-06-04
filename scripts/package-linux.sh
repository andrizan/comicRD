#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
VERSION="${1:-}"

if [ -z "$VERSION" ]; then
  VERSION="$(sed -n 's/^version: \([0-9][^+]*\).*/\1/p' "$ROOT_DIR/app_flutter/pubspec.yaml")"
fi

if [ -z "$VERSION" ]; then
  echo "Unable to resolve version. Pass it as the first argument." >&2
  exit 1
fi

DIST_DIR="$ROOT_DIR/dist"
PACKAGE_NAME="comicrd-${VERSION}-linux-x86_64"
PACKAGE_DIR="$DIST_DIR/$PACKAGE_NAME"
TARBALL="$DIST_DIR/$PACKAGE_NAME.tar.gz"
BUNDLE_DIR="$ROOT_DIR/app_flutter/build/linux/x64/release/bundle"

cd "$ROOT_DIR/app_flutter"
"$FLUTTER_BIN" pub get
"$FLUTTER_BIN" build linux --release

rm -rf "$PACKAGE_DIR" "$TARBALL"
mkdir -p \
  "$PACKAGE_DIR/opt/comicrd" \
  "$PACKAGE_DIR/usr/share/applications" \
  "$PACKAGE_DIR/usr/share/icons/hicolor/512x512/apps" \
  "$PACKAGE_DIR/usr/share/licenses/comicrd-bin"

cp -a "$BUNDLE_DIR/." "$PACKAGE_DIR/opt/comicrd/"
chmod 755 "$PACKAGE_DIR/opt/comicrd/ComicRD"

cat > "$PACKAGE_DIR/usr/share/applications/comicrd.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=ComicRD
Comment=Desktop comic reader
Exec=comicrd
Icon=comicrd
Terminal=false
Categories=Graphics;Viewer;
EOF

cp \
  "$ROOT_DIR/app_flutter/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png" \
  "$PACKAGE_DIR/usr/share/icons/hicolor/512x512/apps/comicrd.png"

if [ -f "$ROOT_DIR/LICENSE" ]; then
  cp "$ROOT_DIR/LICENSE" "$PACKAGE_DIR/usr/share/licenses/comicrd-bin/LICENSE"
fi

mkdir -p "$DIST_DIR"
tar -C "$DIST_DIR" -czf "$TARBALL" "$PACKAGE_NAME"

echo "$TARBALL"
