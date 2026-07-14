param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("windows", "linux", "macos")]
  [string]$Platform,

  [Parameter(Mandatory = $true)]
  [string]$Configuration,

  [Parameter(Mandatory = $true)]
  [string]$Destination
)

$ErrorActionPreference = "Stop"

$RootDir = Resolve-Path (Join-Path $PSScriptRoot "..")
$Profile = if ($Configuration -match "^(Profile|Release)$") { "release" } else { "debug" }

$VcpkgRoot = $env:VCPKG_INSTALLATION_ROOT
if ([string]::IsNullOrWhiteSpace($VcpkgRoot)) {
  $VcpkgRoot = $env:VCPKG_ROOT
}
if ($Platform -eq "windows" -and -not [string]::IsNullOrWhiteSpace($VcpkgRoot)) {
  $VcpkgPkgConfig = Join-Path $VcpkgRoot "installed\x64-windows\lib\pkgconfig"
  if (Test-Path -LiteralPath $VcpkgPkgConfig) {
    if ([string]::IsNullOrWhiteSpace($env:PKG_CONFIG_PATH)) {
      $env:PKG_CONFIG_PATH = $VcpkgPkgConfig
    } elseif ($env:PKG_CONFIG_PATH -notlike "*$VcpkgPkgConfig*") {
      $env:PKG_CONFIG_PATH = "$VcpkgPkgConfig;$env:PKG_CONFIG_PATH"
    }
  }
}
if ($Platform -eq "windows" -and [string]::IsNullOrWhiteSpace($env:SYSTEM_DEPS_DAV1D_BUILD_INTERNAL)) {
  $PkgConfig = Get-Command pkg-config -ErrorAction SilentlyContinue
  if ($null -eq $PkgConfig) {
    throw "pkg-config is required for native AVIF on Windows. Install pkgconfiglite and dav1d via vcpkg, then set PKG_CONFIG_PATH to the vcpkg dav1d pkgconfig directory."
  }

  & pkg-config --exists "dav1d >= 1.3.0"
  if ($LASTEXITCODE -ne 0) {
    throw "Native AVIF requires dav1d on Windows. Run: vcpkg install dav1d:x64-windows; then set PKG_CONFIG_PATH to `$env:VCPKG_INSTALLATION_ROOT\installed\x64-windows\lib\pkgconfig."
  }
}

$LibraryName = switch ($Platform) {
  "windows" { "comicrd_bridge.dll" }
  "linux" { "libcomicrd_bridge.so" }
  "macos" { "libcomicrd_bridge.dylib" }
}

$CargoArgs = @("build", "-p", "comicrd_bridge")
if ($Profile -eq "release") {
  $CargoArgs += "--release"
}

Push-Location $RootDir
try {
  & cargo @CargoArgs
  if ($LASTEXITCODE -ne 0) {
    throw "cargo build failed with exit code $LASTEXITCODE"
  }
} finally {
  Pop-Location
}

$Artifact = Join-Path $RootDir "target\$Profile\$LibraryName"
if (!(Test-Path -LiteralPath $Artifact)) {
  throw "Expected native bridge artifact was not found: $Artifact"
}

New-Item -ItemType Directory -Force -Path $Destination | Out-Null
Copy-Item -LiteralPath $Artifact -Destination (Join-Path $Destination $LibraryName) -Force

if ($Platform -eq "windows" -and -not [string]::IsNullOrWhiteSpace($VcpkgRoot)) {
  $Dav1dDir = if ($Profile -eq "release") { "bin" } else { "debug\bin" }
  $Dav1dDll = Join-Path $VcpkgRoot "installed\x64-windows\$Dav1dDir\dav1d.dll"
  if (Test-Path -LiteralPath $Dav1dDll) {
    Copy-Item -LiteralPath $Dav1dDll -Destination $Destination -Force
    Write-Host "Bundled dav1d.dll from $Dav1dDll to $Destination"
  } else {
    Write-Warning "dav1d.dll not found at $Dav1dDll; the app may fail to load the native bridge at runtime."
  }
}

Write-Host "Bundled $LibraryName from target/$Profile to $Destination"
