$ErrorActionPreference = "Stop"
$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$Patterns = @(
  "BEGIN PRIVATE KEY",
  'credential\s*[:=]\s*[\x22\x27][A-Za-z0-9_-]{24,}[\x22\x27]',
  'dataKey\s*[:=]\s*[\x22\x27][A-Za-z0-9_-]{24,}[\x22\x27]'
)

$Ripgrep = Get-Command rg -ErrorAction SilentlyContinue
if ($null -eq $Ripgrep) {
  throw "VirtualGateway security scan requires rg (ripgrep)."
}

$Failures = @()
foreach ($Pattern in $Patterns) {
  $PatternHits = & $Ripgrep.Source -n --hidden `
    -g "!certs/*.key" `
    -g "!data/**" `
    -g "!reports/**" `
    -g "!**/__pycache__/**" `
    -g "!**/.pytest_cache/**" `
    -g "!scripts/security_scan.ps1" `
    -e $Pattern -- $ProjectRoot
  $ExitCode = $LASTEXITCODE
  if ($ExitCode -eq 0) {
    $Failures += $PatternHits
  } elseif ($ExitCode -gt 1) {
    throw "Security scan failed while evaluating pattern: $Pattern"
  }
}

if ($Failures.Count -gt 0) {
  $Failures | ForEach-Object { Write-Error $_ }
  throw "Sensitive gateway material was found."
}
Write-Host "VirtualGateway security scan passed."
