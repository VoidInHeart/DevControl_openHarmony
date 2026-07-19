param(
  [string]$DevEcoHome = "",
  [ValidateSet("debug", "release")]
  [string]$BuildMode = "debug"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

$DevEcoSource = "parameter -DevEcoHome"
if ([string]::IsNullOrWhiteSpace($DevEcoHome)) {
  # Use the .NET API instead of enumerating Env:. Some Windows launchers can
  # expose environment keys with duplicate casing, which breaks Env: listing.
  $DevEcoHome = [System.Environment]::GetEnvironmentVariable(
    "DEVECO_HOME",
    [System.EnvironmentVariableTarget]::Process
  )
  $DevEcoSource = "environment variable DEVECO_HOME"
}

if ([string]::IsNullOrWhiteSpace($DevEcoHome)) {
  $ProgramFiles = [System.Environment]::GetFolderPath(
    [System.Environment+SpecialFolder]::ProgramFiles
  )
  $CommonHomes = @(
    "D:\tool\DevEco\DevEco Studio",
    "D:\DevEco Studio",
    (Join-Path $ProgramFiles "Huawei\DevEco Studio")
  )
  $DevEcoHome = $CommonHomes | Where-Object {
    Test-Path -LiteralPath (Join-Path $_ "tools\hvigor\bin\hvigorw.bat")
  } | Select-Object -First 1
  $DevEcoSource = "common installation path"
}

if ([string]::IsNullOrWhiteSpace($DevEcoHome)) {
  throw "DevEco Studio was not found. Set DEVECO_HOME or pass -DevEcoHome."
}

$DevEcoHome = [System.IO.Path]::GetFullPath($DevEcoHome.Trim().Trim('"'))
$env:DEVECO_SDK_HOME = Join-Path $DevEcoHome "sdk"
$Hvigor = Join-Path $DevEcoHome "tools\hvigor\bin\hvigorw.bat"
if (-not (Test-Path -LiteralPath $Hvigor)) {
  throw "DevEco Studio from $DevEcoSource has no Hvigor at $Hvigor"
}
Write-Host "Using DevEco Studio from ${DevEcoSource}: $DevEcoHome"

Push-Location $ProjectRoot
try {
  & $Hvigor --mode module -p product=default -p module=entry@default `
    -p buildMode=$BuildMode assembleHap --no-daemon
  if ($LASTEXITCODE -ne 0) {
    throw "HAP build failed with exit code $LASTEXITCODE"
  }
} finally {
  Pop-Location
}
