$ErrorActionPreference = "Stop"
$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$KeyPasswordPattern = '(?i)[\x22\x27]?keyPassword[\x22\x27]?\s*[:=]\s*[\x22\x27][^\x22\x27]+[\x22\x27]'
$StorePasswordPattern = '(?i)[\x22\x27]?storePassword[\x22\x27]?\s*[:=]\s*[\x22\x27][^\x22\x27]+[\x22\x27]'
$CertificatePathPattern = '(?i)[\x22\x27]?certpath[\x22\x27]?\s*[:=]\s*[\x22\x27][A-Za-z]:[\\/]'
$CredentialPattern = '(?i)[\x22\x27]?credential[\x22\x27]?\s*[:=]\s*[\x22\x27][A-Za-z0-9_-]{24,}[\x22\x27]'
$DataKeyPattern = '(?i)[\x22\x27]?dataKey[\x22\x27]?\s*[:=]\s*[\x22\x27][A-Za-z0-9_-]{24,}[\x22\x27]'
$Patterns = @(
  "simulateDevice",
  "xorProcess",
  "tlsConnect",
  "DEFAULT_ENCRYPTION_KEY",
  "BEGIN PRIVATE KEY",
  $KeyPasswordPattern,
  $StorePasswordPattern,
  $CertificatePathPattern,
  $CredentialPattern,
  $DataKeyPattern
)

$PatternSelfTests = @(
  @($KeyPasswordPattern, '"keyPassword": "do-not-commit"'),
  @($StorePasswordPattern, "'storePassword' = 'do-not-commit'"),
  @($CertificatePathPattern, '"certpath": "C:\\private\\debug.cer"'),
  @($CredentialPattern, '"credential": "abcdefghijklmnopqrstuvwxyz012345"'),
  @($DataKeyPattern, "dataKey = 'abcdefghijklmnopqrstuvwxyz012345'")
)
foreach ($TestCase in $PatternSelfTests) {
  if ($TestCase[1] -notmatch $TestCase[0]) {
    throw "Security scan pattern self-test failed for sample: $($TestCase[1])"
  }
}

$Ripgrep = Get-Command rg -ErrorAction SilentlyContinue
$PowerShellFiles = @()
if ($null -eq $Ripgrep) {
  $RootPath = $ProjectRoot.Path.TrimEnd("\")
  $ExcludedDirectories = @(
    ".git",
    ".pytest_cache",
    ".cxx",
    ".hvigor",
    "build",
    "node_modules",
    "oh_modules",
    "artifacts",
    "reports",
    "data"
  )
  $AllowedNames = @(
    ".gitignore",
    "CMakeLists.txt"
  )
  $AllowedExtensions = @(
    ".cfg", ".cmake", ".conf", ".cpp", ".crt", ".cxx", ".ets", ".h",
    ".hpp", ".json", ".json5", ".key", ".md", ".pem", ".properties",
    ".ps1", ".py", ".toml", ".ts", ".txt", ".xml", ".yaml", ".yml"
  )

  # Do not use Get-ChildItem -Recurse here: PowerShell enters an excluded
  # directory before Where-Object can filter it, which fails when a stale
  # pytest cache was created by another Windows account.
  $PendingDirectories = [System.Collections.Generic.Stack[string]]::new()
  $PendingDirectories.Push($ProjectRoot.Path)
  while ($PendingDirectories.Count -gt 0) {
    $CurrentDirectory = $PendingDirectories.Pop()
    try {
      $Children = Get-ChildItem -LiteralPath $CurrentDirectory -Force -ErrorAction Stop
    } catch {
      throw "Security scan cannot read directory: $CurrentDirectory"
    }
    foreach ($Child in $Children) {
      if ($Child.PSIsContainer) {
        $IsReparsePoint = ($Child.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
        if (-not $IsReparsePoint -and $ExcludedDirectories -notcontains $Child.Name) {
          $PendingDirectories.Push($Child.FullName)
        }
        continue
      }

      $RelativePath = $Child.FullName.Substring($RootPath.Length).
        TrimStart("\", "/").Replace("\", "/")
      $IsExcluded = $RelativePath -eq "build-profile.signing.local.json" -or
        $RelativePath -eq "scripts/security_scan.ps1"
      $IsTextFile = $AllowedNames -contains $Child.Name -or
        $AllowedExtensions -contains $Child.Extension.ToLowerInvariant()
      if (-not $IsExcluded -and $IsTextFile -and $Child.Length -le 5MB) {
        $PowerShellFiles += $Child
      }
    }
  }
}

$Failures = @()
foreach ($Pattern in $Patterns) {
  if ($null -ne $Ripgrep) {
    $PatternHits = & $Ripgrep.Source -n --hidden `
      -g "!build-profile.signing.local.json" `
      -g "!**/build/**" `
      -g "!**/.cxx/**" `
      -g "!**/.hvigor/**" `
      -g "!**/.pytest_cache/**" `
      -g "!artifacts/**" `
      -g "!scripts/security_scan.ps1" `
      -e $Pattern -- $ProjectRoot
    $ExitCode = $LASTEXITCODE
    if ($ExitCode -eq 0) {
      $Failures += $PatternHits
    } elseif ($ExitCode -gt 1) {
      throw "Security scan failed while evaluating pattern: $Pattern"
    }
  } else {
    foreach ($File in $PowerShellFiles) {
      $PatternHits = Select-String -LiteralPath $File.FullName -Pattern $Pattern
      foreach ($Hit in $PatternHits) {
        $RelativePath = $File.FullName.Substring($ProjectRoot.Path.Length).
          TrimStart("\", "/").Replace("\", "/")
        $Failures += "{0}:{1}:{2}" -f $RelativePath, $Hit.LineNumber, $Hit.Line.Trim()
      }
    }
  }
}
if ($Failures.Count -gt 0) {
  $Failures | ForEach-Object { Write-Error $_ }
  throw "Sensitive or retired implementation patterns were found."
}
Write-Host "Security scan passed."
