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

# Pastikan pkg-config tersedia di Windows
if ($Platform -eq "windows") {
  $PkgConfig = Get-Command pkg-config -ErrorAction SilentlyContinue
  if ($null -eq $PkgConfig) {
    throw "pkg-config is required for native AVIF on Windows."
  }

  & pkg-config --exists "dav1d >= 1.3.0"
  if ($LASTEXITCODE -ne 0) {
    throw "Native AVIF requires dav1d on Windows. Make sure PKG_CONFIG_PATH is set correctly."
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

Write-Host "Bundled $LibraryName from target/$Profile to $Destination"
