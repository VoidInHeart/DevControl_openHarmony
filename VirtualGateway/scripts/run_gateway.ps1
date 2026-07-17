param(
  [string]$PairingCode = "",
  [string]$HostAddress = "0.0.0.0",
  [int]$Port = 8443,
  [int]$AdminPort = 18444,
  [string]$AdminToken = ""
)

$ErrorActionPreference = "Stop"
$GatewayRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$env:DEVCONTROL_HOST = $HostAddress
$env:DEVCONTROL_PORT = $Port.ToString()
$env:DEVCONTROL_ADMIN_PORT = $AdminPort.ToString()
$env:DEVCONTROL_TLS_CERT = (Join-Path $GatewayRoot "certs\gateway.crt")
$env:DEVCONTROL_TLS_KEY = (Join-Path $GatewayRoot "certs\gateway.key")
$env:DEVCONTROL_DATABASE = (Join-Path $GatewayRoot "data\devcontrol.db")
if (-not (Test-Path -LiteralPath $env:DEVCONTROL_TLS_CERT) -or
    -not (Test-Path -LiteralPath $env:DEVCONTROL_TLS_KEY)) {
  throw "TLS certificate is missing. Run scripts\generate_demo_certs.ps1 first."
}
if ($PairingCode.Length -gt 0) {
  $env:DEVCONTROL_PAIRING_CODE = $PairingCode
}
if ($AdminToken.Length -gt 0) {
  $env:DEVCONTROL_ADMIN_TOKEN = $AdminToken
}
Push-Location $GatewayRoot
try {
  python -m devcontrol_gateway
} finally {
  Pop-Location
}
