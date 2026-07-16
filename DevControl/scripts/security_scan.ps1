$ErrorActionPreference = "Stop"
$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$Patterns = @(
  "simulateDevice",
  "xorProcess",
  "tlsConnect",
  "DEFAULT_ENCRYPTION_KEY",
  "BEGIN PRIVATE KEY",
  '(?i)keyPassword\s*:\s*\x22[^\x22]+\x22',
  '(?i)storePassword\s*:\s*\x22[^\x22]+\x22',
  '(?i)certpath\s*:\s*\x22[A-Za-z]:[\\/]',
  'credential\s*:\s*\x22[A-Za-z0-9_-]{24,}\x22',
  'dataKey\s*:\s*\x22[A-Za-z0-9_-]{24,}\x22'
)

$Failures = @()
foreach ($Pattern in $Patterns) {
  $Matches = & rg -n --hidden `
    -g "!gateway/certs/*.key" `
    -g "!gateway/data/**" `
    -g "!build-profile.signing.local.json" `
    -g "!**/build/**" `
    -g "!**/.cxx/**" `
    -g "!**/.hvigor/**" `
    -g "!scripts/security_scan.ps1" `
    -e $Pattern -- $ProjectRoot
  $ExitCode = $LASTEXITCODE
  if ($ExitCode -eq 0) {
    $Failures += $Matches
  } elseif ($ExitCode -gt 1) {
    throw "Security scan failed while evaluating pattern: $Pattern"
  }
}
if ($Failures.Count -gt 0) {
  $Failures | ForEach-Object { Write-Error $_ }
  throw "Sensitive or retired implementation patterns were found."
}
Write-Host "Security scan passed."
