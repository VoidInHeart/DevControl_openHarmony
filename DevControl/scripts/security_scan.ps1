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
        $RelativePath -eq "scripts/security_scan.ps1" -or
        $RelativePath -like "gateway/certs/*.key"
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
      -g "!gateway/certs/*.key" `
      -g "!gateway/data/**" `
      -g "!gateway/reports/**" `
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
