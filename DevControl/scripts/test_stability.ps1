param(
  [int]$DurationSeconds = 1800
)

$ErrorActionPreference = "Stop"
$GatewayRoot = Resolve-Path (Join-Path $PSScriptRoot "..\gateway")
Push-Location $GatewayRoot
try {
  python scripts/run_e2e_suite.py --performance-count 100 `
    --stability-seconds $DurationSeconds
  if ($LASTEXITCODE -ne 0) {
    throw "Gateway stability test failed."
  }
} finally {
  Pop-Location
}
