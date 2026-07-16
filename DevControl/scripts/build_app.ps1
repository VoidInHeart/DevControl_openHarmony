param(
  [string]$DevEcoHome = "D:\DevEco Studio",
  [ValidateSet("debug", "release")]
  [string]$BuildMode = "debug"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$BuildProfile = Join-Path $ProjectRoot "build-profile.json5"
$LocalSigning = Join-Path $ProjectRoot "build-profile.signing.local.json"
$env:DEVECO_SDK_HOME = Join-Path $DevEcoHome "sdk"
$Hvigor = Join-Path $DevEcoHome "tools\hvigor\bin\hvigorw.bat"
if (-not (Test-Path -LiteralPath $Hvigor)) {
  throw "DevEco Studio Hvigor was not found at $Hvigor"
}

$OriginalProfile = [System.IO.File]::ReadAllText($BuildProfile)
$SigningApplied = $false
try {
  if (Test-Path -LiteralPath $LocalSigning) {
    $Profile = $OriginalProfile | ConvertFrom-Json
    $Signing = Get-Content -Raw -LiteralPath $LocalSigning | ConvertFrom-Json
    if ($null -eq $Signing.signingConfigs -or [string]::IsNullOrWhiteSpace($Signing.productSigningConfig)) {
      throw "Local signing file must define signingConfigs and productSigningConfig."
    }
    $Profile.app | Add-Member -NotePropertyName "signingConfigs" `
      -NotePropertyValue $Signing.signingConfigs -Force
    $Product = $Profile.app.products | Where-Object { $_.name -eq "default" } | Select-Object -First 1
    $Product | Add-Member -NotePropertyName "signingConfig" `
      -NotePropertyValue $Signing.productSigningConfig -Force
    $Rendered = $Profile | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText(
      $BuildProfile,
      $Rendered,
      (New-Object System.Text.UTF8Encoding($false))
    )
    $SigningApplied = $true
  }

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
} finally {
  if ($SigningApplied) {
    [System.IO.File]::WriteAllText(
      $BuildProfile,
      $OriginalProfile,
      (New-Object System.Text.UTF8Encoding($false))
    )
  }
}
