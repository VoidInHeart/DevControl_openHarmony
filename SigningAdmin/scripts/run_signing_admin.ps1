param(
  [ValidateSet("127.0.0.1", "localhost", "::1")]
  [string]$HostAddress = "127.0.0.1",
  [ValidateRange(1, 65535)]
  [int]$Port = 18445
)

$ErrorActionPreference = "Stop"
$SigningAdminRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$WorkspaceRoot = (Resolve-Path -LiteralPath (Join-Path $SigningAdminRoot "..")).Path
Push-Location $SigningAdminRoot
try {
  python -m signing_admin.app --host $HostAddress --port $Port --workspace-root $WorkspaceRoot
} finally {
  Pop-Location
}
