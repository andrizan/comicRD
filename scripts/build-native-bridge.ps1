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
$RtkBin = if ($env:RTK_BIN) { $env:RTK_BIN } else { "rtk" }

$LibraryName = switch ($Platform) {
  "windows" { "comicrd_bridge.dll" }
  "linux" { "libcomicrd_bridge.so" }
  "macos" { "libcomicrd_bridge.dylib" }
}

$CargoArgs = @("cargo", "build", "-p", "comicrd_bridge")
if ($Profile -eq "release") {
  $CargoArgs += "--release"
}

Push-Location $RootDir
try {
  & $RtkBin @CargoArgs
  if ($LASTEXITCODE -ne 0) {
    throw "rtk cargo build failed with exit code $LASTEXITCODE"
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
