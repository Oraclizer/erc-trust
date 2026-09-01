param(
  [Parameter(Mandatory = $true)]
  [string]$ForgeExecutable,
  [string]$TemporaryBaseDirectory = 'C:\tmp',
  [string]$OutputPath,
  [switch]$UseWslForge,
  [switch]$CheckReceipt
)

$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $repoRoot 'evidence\deterministic-build.json'
}
$temporaryBase = [System.IO.Path]::GetFullPath($TemporaryBaseDirectory).TrimEnd(
  [System.IO.Path]::DirectorySeparatorChar,
  [System.IO.Path]::AltDirectorySeparatorChar)
$runRoot = [System.IO.Path]::GetFullPath(
  (Join-Path $temporaryBase 'erc-trust-candidate-deterministic-build'))

if (
  -not [System.IO.Path]::GetDirectoryName($runRoot).Equals(
    $temporaryBase,
    [System.StringComparison]::OrdinalIgnoreCase) -or
  -not [System.IO.Path]::GetFileName($runRoot).Equals(
    'erc-trust-candidate-deterministic-build',
    [System.StringComparison]::Ordinal)
) {
  throw "Refusing unsafe deterministic-build root: $runRoot"
}

function Remove-GuardedDirectory([string]$Path) {
  $resolved = [System.IO.Path]::GetFullPath($Path)
  if (-not $resolved.StartsWith(
      $runRoot + [System.IO.Path]::DirectorySeparatorChar,
      [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing unsafe cleanup: $resolved"
  }
  if (Test-Path -LiteralPath $resolved) {
    Remove-Item -LiteralPath $resolved -Recurse -Force
  }
}

function Get-Sha256Bytes([byte[]]$Bytes) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return (
      [System.BitConverter]::ToString($sha.ComputeHash($Bytes))
    ).Replace('-', '').ToLowerInvariant()
  }
  finally {
    $sha.Dispose()
  }
}

function Convert-HexToBytes([string]$Hex) {
  if (($Hex.Length % 2) -ne 0) {
    throw 'Hex input has an odd length'
  }
  $bytes = [byte[]]::new($Hex.Length / 2)
  for ($index = 0; $index -lt $bytes.Length; $index++) {
    $bytes[$index] = [Convert]::ToByte($Hex.Substring($index * 2, 2), 16)
  }
  return $bytes
}

function Invoke-Forge([string[]]$Arguments) {
  if ($UseWslForge) {
    $output = @(& wsl.exe -d Ubuntu -e /usr/local/bin/forge @Arguments 2>&1)
  }
  else {
    $output = @(& $ForgeExecutable @Arguments 2>&1)
  }
  $script:LastForgeExitCode = $LASTEXITCODE
  return $output
}

$versionOutput = @(Invoke-Forge @('--version'))
if ($script:LastForgeExitCode -ne 0) {
  throw 'Unable to execute the pinned Foundry toolchain'
}
$versionText = $versionOutput -join "`n"
if (
  $versionText -notmatch 'forge Version:\s*1\.7\.1' -or
  $versionText -notmatch 'Commit SHA:\s*4072e48705af9d93e3c0f6e29e93b5e9a40caed8'
) {
  throw "Unexpected Foundry toolchain identity`n$versionText"
}

function Invoke-IsolatedBuild([string]$Name) {
  $directory = Join-Path $runRoot $Name
  Remove-GuardedDirectory $directory
  [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  Copy-Item -LiteralPath (Join-Path $repoRoot 'foundry.toml') `
    -Destination (Join-Path $directory 'foundry.toml')
  Copy-Item -LiteralPath (Join-Path $repoRoot 'implementation') `
    -Destination (Join-Path $directory 'implementation') -Recurse

  $previousErrorAction = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $forgeRoot = $directory
  if ($UseWslForge) {
    $forgeRoot = (@(& wsl.exe -d Ubuntu -e wslpath -a $directory) -join '').Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($forgeRoot)) {
      throw "Unable to translate isolated build root for WSL: $directory"
    }
  }
  $buildOutput = @(Invoke-Forge @('build', '--root', $forgeRoot, '--force'))
  $buildExitCode = $script:LastForgeExitCode
  $ErrorActionPreference = $previousErrorAction
  if ($buildExitCode -ne 0) {
    throw (
      "Isolated build $Name failed with exit code $buildExitCode`n" +
      ($buildOutput -join "`n"))
  }

  $artifactPath = Join-Path $directory 'out\TrustToken.sol\TrustToken.json'
  $artifactBytes = [System.IO.File]::ReadAllBytes($artifactPath)
  $artifact = Get-Content -LiteralPath $artifactPath -Raw | ConvertFrom-Json
  $creationBytes = Convert-HexToBytes ($artifact.bytecode.object.Substring(2))
  $runtimeBytes = Convert-HexToBytes (
    $artifact.deployedBytecode.object.Substring(2))
  return [ordered]@{
    artifactSha256 = Get-Sha256Bytes $artifactBytes
    creationSha256 = Get-Sha256Bytes $creationBytes
    runtimeSha256 = Get-Sha256Bytes $runtimeBytes
    creationBytes = $creationBytes.Length
    runtimeBytes = $runtimeBytes.Length
  }
}

[System.IO.Directory]::CreateDirectory($runRoot) | Out-Null
$buildA = Invoke-IsolatedBuild 'build-a'
$buildB = Invoke-IsolatedBuild 'build-b'
$pass = (
  $buildA.artifactSha256 -eq $buildB.artifactSha256 -and
  $buildA.creationSha256 -eq $buildB.creationSha256 -and
  $buildA.runtimeSha256 -eq $buildB.runtimeSha256 -and
  $buildA.creationBytes -eq $buildB.creationBytes -and
  $buildA.runtimeBytes -eq $buildB.runtimeBytes
)

$result = [ordered]@{
  schema = 'erc-trust-deterministic-build-v1'
  status = if ($pass) { 'PASS' } else { 'FAIL' }
  toolchain = [ordered]@{
    forge = '1.7.1'
    forgeCommit = '4072e48705af9d93e3c0f6e29e93b5e9a40caed8'
    solidity = '0.8.36+commit.8a079791'
    evmVersion = 'cancun'
    optimizerRuns = 1
    viaIR = $true
    bytecodeHash = 'none'
    cborMetadata = $false
  }
  buildA = $buildA
  buildB = $buildB
}

[System.IO.Directory]::CreateDirectory($runRoot) | Out-Null
[System.IO.Directory]::CreateDirectory(
  [System.IO.Path]::GetDirectoryName(
    [System.IO.Path]::GetFullPath($OutputPath))) | Out-Null
$resultText = ($result | ConvertTo-Json -Depth 10) + "`n"
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
if ($CheckReceipt) {
  if (-not (Test-Path -LiteralPath $resolvedOutput)) {
    throw "Deterministic build receipt missing: $resolvedOutput"
  }
  if ([System.IO.File]::ReadAllText($resolvedOutput) -ne $resultText) {
    throw 'Deterministic build receipt drift'
  }
}
else {
  [System.IO.File]::WriteAllText(
    $resolvedOutput,
    $resultText,
    [System.Text.UTF8Encoding]::new($false))
}

Remove-GuardedDirectory (Join-Path $runRoot 'build-a')
Remove-GuardedDirectory (Join-Path $runRoot 'build-b')
if ((Get-ChildItem -LiteralPath $runRoot -Force | Measure-Object).Count -eq 0) {
  Remove-Item -LiteralPath $runRoot -Force
}

if (-not $pass) {
  throw 'Isolated build outputs are not byte-for-byte deterministic'
}
Write-Output (
  "deterministic build PASS: runtime $($buildA.runtimeBytes) bytes, " +
  "artifact $($buildA.artifactSha256)")
