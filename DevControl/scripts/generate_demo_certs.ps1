param(
  [string]$HostName = "localhost",
  [string]$IpAddress = "127.0.0.1"
)

$ErrorActionPreference = "Stop"
$GatewayRoot = Resolve-Path (Join-Path $PSScriptRoot "..\gateway")
Push-Location $GatewayRoot
try {
  python scripts/generate_demo_certs.py --host $HostName --ip $IpAddress
  if ($LASTEXITCODE -ne 0) {
    throw "Demo certificate generation failed."
  }
} finally {
  Pop-Location
}
