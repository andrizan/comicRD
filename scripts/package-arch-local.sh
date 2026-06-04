#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-}"

if [ -z "$VERSION" ]; then
  VERSION="$(sed -n 's/^version: \([0-9][^+]*\).*/\1/p' "$ROOT_DIR/app_flutter/pubspec.yaml")"
fi

if [ -z "$VERSION" ]; then
  echo "Unable to resolve version. Pass it as the first argument." >&2
  exit 1
fi

TARBALL="$ROOT_DIR/dist/comicrd-${VERSION}-linux-x86_64.tar.gz"
if [ ! -f "$TARBALL" ]; then
  "$ROOT_DIR/scripts/package-linux.sh" "$VERSION"
fi

PKGDIR="$ROOT_DIR/dist/arch"
rm -rf "$PKGDIR"
mkdir -p "$PKGDIR"
cp "$TARBALL" "$PKGDIR/"

SHA256="$(sha256sum "$PKGDIR/$(basename "$TARBALL")" | awk '{print $1}')"

cat > "$PKGDIR/PKGBUILD" <<PKGEOF
pkgname=comicrd-bin
_pkgname=comicrd
pkgver=${VERSION}
pkgrel=1
pkgdesc="ComicRD desktop comic reader built with Flutter and Rust"
arch=('x86_64')
url="https://github.com/andrizan/comicrd_flutter"
license=('MIT')
depends=(
  'gcc-libs'
  'glib2'
  'glibc'
  'gtk3'
  'hicolor-icon-theme'
  'libepoxy'
)
provides=('comicrd')
conflicts=('comicrd')
source=("\${_pkgname}-\${pkgver}-linux-x86_64.tar.gz")
sha256sums=('${SHA256}')

package() {
  cp -R --no-preserve=ownership "\${srcdir}/comicrd-\${pkgver}-linux-x86_64/opt" "\${pkgdir}/"
  install -dm755 "\${pkgdir}/usr/bin"
  ln -sf /opt/comicrd/ComicRD "\${pkgdir}/usr/bin/comicrd"
  install -Dm644 "\${srcdir}/comicrd-\${pkgver}-linux-x86_64/usr/share/applications/comicrd.desktop" "\${pkgdir}/usr/share/applications/comicrd.desktop"
  install -Dm644 "\${srcdir}/comicrd-\${pkgver}-linux-x86_64/usr/share/icons/hicolor/512x512/apps/comicrd.png" "\${pkgdir}/usr/share/icons/hicolor/512x512/apps/comicrd.png"
  install -Dm644 "\${srcdir}/comicrd-\${pkgver}-linux-x86_64/usr/share/licenses/comicrd-bin/LICENSE" "\${pkgdir}/usr/share/licenses/comicrd-bin/LICENSE"
}
PKGEOF

(
  cd "$PKGDIR"
  makepkg -f --clean
)

ls -1 "$PKGDIR"/*.pkg.tar.zst
