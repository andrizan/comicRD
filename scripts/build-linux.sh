#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="x86_64-unknown-linux-gnu"
MODE="${1:-deb-rpm}"
VERSION="$(node -p "require('${ROOT_DIR}/package.json').version")"
OUT_DIR="${ROOT_DIR}/release/linux"

usage() {
  cat <<'EOF'
Usage:
  scripts/build-linux.sh deb-rpm   Build Tauri .deb and .rpm bundles
  scripts/build-linux.sh appimage  Build Tauri AppImage bundle
  scripts/build-linux.sh arch      Build Arch/CachyOS tarball + PKGBUILD + local package
  scripts/build-linux.sh all       Build deb/rpm, AppImage, and Arch package

Notes:
  - This script mirrors .github/workflows/desktop-build.yml.
  - Arch mode uses `tauri build --no-bundle` so the Tauri production asset pipeline runs.
EOF
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

print_linux_deps_hint() {
  if command -v pacman >/dev/null 2>&1; then
    cat <<'EOF'
Arch/CachyOS dependencies:
  sudo pacman -S --needed base-devel git rust curl wget file openssl gtk3 webkit2gtk-4.1 libayatana-appindicator librsvg xdotool patchelf desktop-file-utils
EOF
  elif command -v apt-get >/dev/null 2>&1; then
    cat <<'EOF'
Ubuntu/Debian dependencies:
  sudo apt-get install -y build-essential curl wget file libssl-dev libgtk-3-dev libayatana-appindicator3-dev librsvg2-dev libwebkit2gtk-4.1-dev libxdo-dev patchelf rpm
EOF
  fi
}

prepare() {
  need_cmd node
  need_cmd pnpm
  need_cmd cargo

  mkdir -p "${OUT_DIR}"
  print_linux_deps_hint
}

install_js_deps() {
  if [[ -f "${ROOT_DIR}/pnpm-lock.yaml" ]]; then
    pnpm install --frozen-lockfile
  else
    pnpm install
  fi
}

build_deb_rpm() {
  prepare
  install_js_deps
  pnpm run tauri:build:linux

  find "${ROOT_DIR}/src-tauri/target/${TARGET}/release/bundle" \
    -type f \( -name "*.deb" -o -name "*.rpm" \) \
    -exec cp -v {} "${OUT_DIR}/" \;
}

build_appimage() {
  prepare
  install_js_deps
  pnpm run tauri:build:linux:appimage

  find "${ROOT_DIR}/src-tauri/target/${TARGET}/release/bundle/appimage" \
    -type f -name "*.AppImage" \
    -exec cp -v {} "${OUT_DIR}/" \;
}

build_arch() {
  prepare
  need_cmd tar
  need_cmd sha256sum

  install_js_deps
  pnpm tauri build --target "${TARGET}" --no-bundle

  local pkg_root="${ROOT_DIR}/pkgbuild"
  local src_dir="${pkg_root}/src/comicrd-${VERSION}"
  local tarball="${pkg_root}/comicrd-${VERSION}-linux-x86_64.tar.gz"

  rm -rf "${pkg_root}"
  mkdir -p "${src_dir}"

  install -Dm755 \
    "${ROOT_DIR}/src-tauri/target/${TARGET}/release/comicrd" \
    "${src_dir}/comicrd"

  cat >"${src_dir}/comicrd.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=ComicRD
Comment=ComicRD Desktop App
Exec=comicrd
Icon=comicrd
Terminal=false
Categories=Utility;
EOF

  if [[ -f "${ROOT_DIR}/src-tauri/icons/128x128.png" ]]; then
    install -Dm644 "${ROOT_DIR}/src-tauri/icons/128x128.png" "${src_dir}/comicrd.png"
  fi

  if [[ -f "${ROOT_DIR}/LICENSE" ]]; then
    install -Dm644 "${ROOT_DIR}/LICENSE" "${src_dir}/LICENSE"
  fi

  (
    cd "${pkg_root}/src"
    tar -czf "${tarball}" "comicrd-${VERSION}"
  )

  local sha256
  sha256="$(sha256sum "${tarball}" | awk '{print $1}')"

  cat >"${pkg_root}/PKGBUILD" <<EOF
pkgname=comicrd-bin
pkgver=${VERSION}
pkgrel=1
pkgdesc="ComicRD desktop app"
arch=('x86_64')
url="https://github.com/andrizan/comicRD"
license=('custom')
depends=(
  'webkit2gtk-4.1'
  'gtk3'
  'libayatana-appindicator'
  'librsvg'
  'openssl'
  'hicolor-icon-theme'
)
provides=('comicrd')
conflicts=('comicrd')
source=("comicrd-\${pkgver}-linux-x86_64.tar.gz")
sha256sums=('${sha256}')

package() {
  install -Dm755 "\${srcdir}/comicrd-\${pkgver}/comicrd" "\${pkgdir}/usr/bin/comicrd"
  install -Dm644 "\${srcdir}/comicrd-\${pkgver}/comicrd.desktop" "\${pkgdir}/usr/share/applications/comicrd.desktop"

  if [ -f "\${srcdir}/comicrd-\${pkgver}/comicrd.png" ]; then
    install -Dm644 "\${srcdir}/comicrd-\${pkgver}/comicrd.png" "\${pkgdir}/usr/share/icons/hicolor/128x128/apps/comicrd.png"
  fi

  if [ -f "\${srcdir}/comicrd-\${pkgver}/LICENSE" ]; then
    install -Dm644 "\${srcdir}/comicrd-\${pkgver}/LICENSE" "\${pkgdir}/usr/share/licenses/comicrd-bin/LICENSE"
  fi
}
EOF

  if command -v makepkg >/dev/null 2>&1; then
    (
      cd "${pkg_root}"
      makepkg --printsrcinfo >.SRCINFO
      makepkg -f --clean
    )
    find "${pkg_root}" -maxdepth 1 -type f -name "*.pkg.tar.zst" -exec cp -v {} "${OUT_DIR}/" \;
  else
    echo "makepkg not found; generated PKGBUILD and tarball only."
  fi

  cp -v "${tarball}" "${pkg_root}/PKGBUILD" "${OUT_DIR}/"
  if [[ -f "${pkg_root}/.SRCINFO" ]]; then
    cp -v "${pkg_root}/.SRCINFO" "${OUT_DIR}/"
  fi
}

case "${MODE}" in
  deb-rpm)
    build_deb_rpm
    ;;
  appimage)
    build_appimage
    ;;
  arch)
    build_arch
    ;;
  all)
    build_deb_rpm
    build_appimage
    build_arch
    ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    usage
    exit 1
    ;;
esac

echo "Linux build outputs:"
find "${OUT_DIR}" -maxdepth 1 -type f -print | sort
