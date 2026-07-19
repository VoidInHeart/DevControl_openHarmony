param(
  [string]$InitialPairingCode = "",
  [string]$HostAddress = "0.0.0.0",
  [int]$Port = 8443,
  [int]$AdminPort = 18444,
  [ValidateRange(1, 31536000)]
  [int]$CredentialTtlSeconds = 86400,
  [string]$AdminToken = "",
  [switch]$EnableMqtt,
  [string]$MqttHost = "",
  [int]$MqttPort = 8883,
  [string]$MqttCa = "",
  [string]$MqttClientCert = "",
  [string]$MqttClientKey = ""
)

$ErrorActionPreference = "Stop"
$GatewayRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$env:DEVCONTROL_HOST = $HostAddress
$env:DEVCONTROL_PORT = $Port.ToString()
$env:DEVCONTROL_ADMIN_PORT = $AdminPort.ToString()
$env:DEVCONTROL_CREDENTIAL_TTL_SECONDS = $CredentialTtlSeconds.ToString()
$env:DEVCONTROL_MQTT_ENABLED = if ($EnableMqtt) { "true" } else { "false" }
$env:DEVCONTROL_TLS_CERT = (Join-Path $GatewayRoot "certs\gateway.crt")
$env:DEVCONTROL_TLS_KEY = (Join-Path $GatewayRoot "certs\gateway.key")
$env:DEVCONTROL_DATABASE = (Join-Path $GatewayRoot "data\devcontrol.db")
if (-not (Test-Path -LiteralPath $env:DEVCONTROL_TLS_CERT) -or
    -not (Test-Path -LiteralPath $env:DEVCONTROL_TLS_KEY)) {
  throw "TLS certificate is missing. Run scripts\generate_demo_certs.ps1 first."
}
if ($InitialPairingCode.Length -gt 0) {
  $env:DEVCONTROL_INITIAL_PAIRING_CODE = $InitialPairingCode
}
if ($AdminToken.Length -gt 0) {
  $env:DEVCONTROL_ADMIN_TOKEN = $AdminToken
}
if ($EnableMqtt) {
  if ($MqttHost.Length -eq 0 -or $MqttCa.Length -eq 0) {
    throw "MQTT requires -MqttHost and -MqttCa. Client authentication must be supplied by mTLS parameters or DEVCONTROL_MQTT_USERNAME/PASSWORD."
  }
  $env:DEVCONTROL_MQTT_HOST = $MqttHost
  $env:DEVCONTROL_MQTT_PORT = $MqttPort.ToString()
  $env:DEVCONTROL_MQTT_CA = (Resolve-Path -LiteralPath $MqttCa).Path
  if (($MqttClientCert.Length -eq 0) -ne ($MqttClientKey.Length -eq 0)) {
    throw "-MqttClientCert and -MqttClientKey must be supplied together."
  }
  if ($MqttClientCert.Length -gt 0) {
    $env:DEVCONTROL_MQTT_CLIENT_CERT = (Resolve-Path -LiteralPath $MqttClientCert).Path
    $env:DEVCONTROL_MQTT_CLIENT_KEY = (Resolve-Path -LiteralPath $MqttClientKey).Path
  }
}
Push-Location $GatewayRoot
try {
  python -m devcontrol_gateway
} finally {
  Pop-Location
}
