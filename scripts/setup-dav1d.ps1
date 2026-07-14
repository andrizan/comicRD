$ErrorActionPreference = "Stop"

Write-Host "==> Checking Visual Studio..."

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"

if (!(Test-Path $vswhere)) {
    throw "vswhere.exe tidak ditemukan. Install Visual Studio Build Tools."
}

$vsPath = & $vswhere `
    -latest `
    -products * `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -property installationPath

if (-not $vsPath) {
    throw "Visual Studio C++ Build Tools tidak ditemukan."
}

$vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"

cmd /c "call `"$vcvars`" && set" |
ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') {
        Set-Item -Path "env:$($matches[1])" -Value $matches[2]
    }
}

Write-Host "==> Installing tools..."

if (-not (Get-Command meson -ErrorAction SilentlyContinue)) {
    pip install meson
}

if (-not (Get-Command ninja -ErrorAction SilentlyContinue)) {
    choco install ninja -y
}

if (-not (Get-Command pkg-config -ErrorAction SilentlyContinue)) {
    choco install pkgconfiglite -y
}

if (-not (Get-Command nasm -ErrorAction SilentlyContinue)) {
    choco install nasm -y
}

$temp = Join-Path $env:TEMP "dav1d-build"
$prefix = Join-Path $env:LOCALAPPDATA "dav1d"

Remove-Item $temp -Recurse -Force -ErrorAction Ignore

git clone --depth 1 --branch 1.5.3 https://code.videolan.org/videolan/dav1d.git $temp

Push-Location $temp

meson setup build `
    --prefix="$prefix" `
    --buildtype=release `
    --default-library=static `
    -Denable_tools=false `
    -Denable_tests=false `
    -Denable_docs=false

meson compile -C build
meson install -C build

Pop-Location

$pkg = "$prefix\lib\pkgconfig"

[Environment]::SetEnvironmentVariable(
    "PKG_CONFIG_PATH",
    $pkg,
    "User"
)

$env:PKG_CONFIG_PATH = $pkg

Write-Host ""
Write-Host "Installed to:"
Write-Host $prefix
Write-Host ""

pkg-config --modversion dav1d
pkg-config --libs dav1d
