$ErrorActionPreference = "Stop"
$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$CredentialPattern = '(?i)[\x22\x27]?credential[\x22\x27]?\s*[:=]\s*[\x22\x27][A-Za-z0-9_-]{24,}[\x22\x27]'
$DataKeyPattern = '(?i)[\x22\x27]?dataKey[\x22\x27]?\s*[:=]\s*[\x22\x27][A-Za-z0-9_-]{24,}[\x22\x27]'
$Patterns = @(
  "BEGIN PRIVATE KEY",
  $CredentialPattern,
  $DataKeyPattern
)

$PatternSelfTests = @(
  @($CredentialPattern, '"credential": "abcdefghijklmnopqrstuvwxyz012345"'),
  @($DataKeyPattern, "'dataKey' = 'abcdefghijklmnopqrstuvwxyz012345'")
)
foreach ($TestCase in $PatternSelfTests) {
  if ($TestCase[1] -notmatch $TestCase[0]) {
    throw "Security scan pattern self-test failed for sample: $($TestCase[1])"
  }
}

$Ripgrep = Get-Command rg -ErrorAction SilentlyContinue
if ($null -eq $Ripgrep) {
  throw "VirtualGateway security scan requires rg (ripgrep)."
}

$Failures = @()
$Git = Get-Command git -ErrorAction SilentlyContinue
if ($null -ne $Git) {
  $TrackedPrivateKeys = & $Git.Source -C $ProjectRoot.Path `
    ls-files --full-name -- "certs/*.key" "certs/*.p12" "certs/*.pfx"
  if ($LASTEXITCODE -ne 0) {
    throw "VirtualGateway security scan could not inspect tracked certificate keys."
  }
  foreach ($TrackedPrivateKey in $TrackedPrivateKeys) {
    $Failures += "Tracked private-key material: $TrackedPrivateKey"
  }
}
foreach ($Pattern in $Patterns) {
  $PatternHits = & $Ripgrep.Source -n --hidden `
    -g "!certs/*.key" `
    -g "!certs/*.p12" `
    -g "!certs/*.pfx" `
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
