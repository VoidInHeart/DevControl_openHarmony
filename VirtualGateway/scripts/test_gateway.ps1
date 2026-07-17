$ErrorActionPreference = "Stop"
$GatewayRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TempRoot = [System.IO.Path]::GetTempPath()
$PytestTemp = Join-Path $TempRoot (
  "DevControl-pytest-{0}-{1}" -f $PID, [Guid]::NewGuid().ToString("N")
)
Push-Location $GatewayRoot
try {
  # Avoid stale pytest directories created by another Windows account or
  # sandbox. The cache is unnecessary for this reproducible verification run.
  python -m pytest -p no:cacheprovider --basetemp $PytestTemp
  if ($LASTEXITCODE -ne 0) {
    throw "Gateway unit tests failed."
  }
  python scripts/run_e2e_suite.py
  if ($LASTEXITCODE -ne 0) {
    throw "Gateway end-to-end tests failed."
  }
} finally {
  Pop-Location
  $ResolvedTempRoot = [System.IO.Path]::GetFullPath($TempRoot).TrimEnd("\") + "\"
  $ResolvedPytestTemp = [System.IO.Path]::GetFullPath($PytestTemp)
  if ($ResolvedPytestTemp.StartsWith(
      $ResolvedTempRoot,
      [System.StringComparison]::OrdinalIgnoreCase
    ) -and
    [System.IO.Path]::GetFileName($ResolvedPytestTemp).StartsWith(
      "DevControl-pytest-",
      [System.StringComparison]::OrdinalIgnoreCase
    ) -and
    (Test-Path -LiteralPath $ResolvedPytestTemp)) {
    Remove-Item -LiteralPath $ResolvedPytestTemp -Recurse -Force
  }
}
