$ErrorActionPreference = "Stop"
$GatewayRoot = Resolve-Path (Join-Path $PSScriptRoot "..\gateway")
Push-Location $GatewayRoot
try {
  python -m pytest
  if ($LASTEXITCODE -ne 0) {
    throw "Gateway unit tests failed."
  }
  python scripts/run_e2e_suite.py
  if ($LASTEXITCODE -ne 0) {
    throw "Gateway end-to-end tests failed."
  }
} finally {
  Pop-Location
}
