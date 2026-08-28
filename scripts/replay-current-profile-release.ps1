[CmdletBinding()]
param(
  [string]$RepositoryRoot = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = Split-Path -Parent $PSScriptRoot
}
$RepositoryRoot = (Resolve-Path $RepositoryRoot).Path

Push-Location $RepositoryRoot
try {
  node scripts/verify-current-profile-release.mjs
  if ($LASTEXITCODE -ne 0) { throw "current-profile release verification failed with exit $LASTEXITCODE" }
  node scripts/verify-runtime-binding.mjs --check-receipt
  if ($LASTEXITCODE -ne 0) { throw "runtime-binding receipt verification failed with exit $LASTEXITCODE" }
  node scripts/verify-release.mjs
  if ($LASTEXITCODE -ne 0) { throw "release binding verification failed with exit $LASTEXITCODE" }
}
finally {
  Pop-Location
}
