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
  node scripts/verify-current-profile-release-v3.mjs
  if ($LASTEXITCODE -ne 0) { throw "successor evidence lane verification failed with exit $LASTEXITCODE" }
  node scripts/verify-obligation-ledger-v3.mjs
  if ($LASTEXITCODE -ne 0) { throw "obligation ledger verification failed with exit $LASTEXITCODE" }
  node scripts/verify-release.mjs
  if ($LASTEXITCODE -ne 0) { throw "release binding verification failed with exit $LASTEXITCODE" }
}
finally {
  Pop-Location
}
