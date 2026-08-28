param(
  [string]$OutputDirectory,
  [string]$IsabelleVersion = 'Isabelle2025-2',
  [Parameter(Mandatory = $true)]
  [string]$IsabelleRoot,
  [Parameter(Mandatory = $true)]
  [string]$AdsFunctor,
  [Parameter(Mandatory = $true)]
  [string]$FormalFoundation
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
  $OutputDirectory = Join-Path $PSScriptRoot 'out'
}
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$sessionDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $sessionDir '..'))
$foundationDir = [System.IO.Path]::GetFullPath($FormalFoundation)
$foundationParent = [System.IO.Path]::GetDirectoryName($foundationDir)
$checkerPath = Join-Path $PSScriptRoot 'reverse-check-manifest.mjs'

function Get-Sha256Bytes([byte[]]$Bytes) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([System.BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '')
  }
  finally {
    $sha.Dispose()
  }
}

function Get-Sha256File([string]$Path) {
  return Get-Sha256Bytes ([System.IO.File]::ReadAllBytes($Path))
}

function Write-Utf8Lf([string]$Path, [string]$Text) {
  $normalized = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
  [System.IO.File]::WriteAllText($Path, $normalized, $utf8NoBom)
}

function To-CanonicalJson($Value) {
  return ($Value | ConvertTo-Json -Compress -Depth 20)
}

function Convert-ToCygwinPath([string]$WindowsPath) {
  $full = [System.IO.Path]::GetFullPath($WindowsPath)
  $drive = $full.Substring(0, 1).ToLowerInvariant()
  $tail = $full.Substring(2).Replace('\', '/')
  return "/cygdrive/$drive$tail"
}

$sourceFiles = @(
  'ROOTS',
  'Cross_Domain_State_Preservation/ROOT',
  'Cross_Domain_State_Preservation/State_Preservation.thy',
  'Cross_Domain_State_Preservation/Regulatory_Instance.thy',
  'Cross_Domain_State_Preservation/Regulatory_Action_Composition.thy',
  'ERC_TRUST/ROOT',
  'ERC_TRUST/Regulatory_Execution_Semantics.thy',
  'ERC_TRUST/RCP_Action_Mapping.thy',
  'ERC_TRUST/Token_Compatibility.thy',
  'ERC_TRUST/Regulatory_Execution_Simulation.thy',
  'ERC_TRUST/Privileged_Governance.thy',
  'ERC_TRUST/Executable_Regulatory_Kernel.thy',
  'ERC_TRUST/Claim_Boundary.thy',
  'ERC_TRUST/Proof_Audit.thy',
  'ERC_TRUST/evidence/model-verification/model-claim-matrix.md',
  'ERC_TRUST/evidence/model-verification/generate-manifest.ps1',
  'ERC_TRUST/evidence/model-verification/run-negative-mutations.ps1',
  'ERC_TRUST/evidence/model-verification/run-trust-closure.ps1',
  'ERC_TRUST/evidence/model-verification/reverse-check-manifest.mjs'
)
$hashLines = [System.Collections.Generic.List[string]]::new()
foreach ($relativePath in $sourceFiles) {
  $nativeRelativePath = $relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
  $sourceRoot = if ($relativePath.StartsWith(
      'Cross_Domain_State_Preservation/',
      [System.StringComparison]::Ordinal)) {
    $foundationParent
  } else {
    $repoRoot
  }
  $absolutePath = Join-Path $sourceRoot $nativeRelativePath
  if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
    throw "Required source file is missing: $relativePath"
  }
  $hash = Get-Sha256File $absolutePath
  $length = (Get-Item -LiteralPath $absolutePath).Length
  $hashLines.Add("$relativePath`t$hash`t$length")
}
$hashListText = (($hashLines | Sort-Object -CaseSensitive) -join "`n") + "`n"
$sourceHashListHash = Get-Sha256Bytes ($utf8NoBom.GetBytes($hashListText))

[System.IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
$kernelRunId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
$kernelExportDirectory = Join-Path $OutputDirectory "kernel-export-generator\$kernelRunId"
$isabelleBash = Join-Path $IsabelleRoot 'contrib\cygwin\bin\bash.exe'
$isabelle = "$(Convert-ToCygwinPath $IsabelleRoot)/bin/isabelle"
$sessionCyg = Convert-ToCygwinPath $sessionDir
$repoCyg = Convert-ToCygwinPath $repoRoot
$adsCyg = Convert-ToCygwinPath $AdsFunctor
$foundationCyg = Convert-ToCygwinPath $foundationDir
$kernelExportCyg = Convert-ToCygwinPath $kernelExportDirectory
$exportCommand = "export PATH=/usr/local/bin:/usr/bin:/bin; '$isabelle' export -d '$adsCyg' -d '$foundationCyg' -d '$repoCyg' -x '*:erc-trust/*-kernel.tsv' -O '$kernelExportCyg' ERC_TRUST"
$exportOutput = @(& $isabelleBash --noprofile --norc -c $exportCommand 2>&1)
if ($LASTEXITCODE -ne 0) {
  throw "Isabelle kernel export failed:`n$($exportOutput -join "`n")"
}
$trustKernelFile = Get-ChildItem -LiteralPath $kernelExportDirectory `
  -Filter 'trust-kernel.tsv' -File -Recurse | Select-Object -First 1
$foundationKernelFile = Get-ChildItem -LiteralPath $kernelExportDirectory `
  -Filter 'foundation-kernel.tsv' -File -Recurse | Select-Object -First 1
if ($null -eq $trustKernelFile -or $null -eq $foundationKernelFile) {
  throw 'Isabelle kernel TSV exports are incomplete'
}

$trustRows = [System.Collections.Generic.List[object]]::new()
foreach ($line in [System.IO.File]::ReadAllLines($trustKernelFile.FullName)) {
  $columns = $line.Split([char]"`t")
  if ($columns.Count -ne 13) {
    throw "Invalid TRUST kernel TSV row: $line"
  }
  $rowWriteSet = [System.Collections.Generic.List[string]]::new()
  if ($columns[12].Length -ne 0) {
    foreach ($slot in $columns[12].Split(';')) {
      $rowWriteSet.Add($slot)
    }
  }
  $trustRows.Add([ordered]@{
    key = $columns[0]
    input = [ordered]@{
      action = $columns[1]
      scenario = $columns[2]
      initialState = $columns[3]
    }
    command = $columns[4]
    outcome = $columns[5]
    targetState = if ($columns[6] -eq '-') { $null } else { $columns[6] }
    rcpAction = $columns[1]
    descriptor = [ordered]@{
      reversibility = $columns[7]
      ownership = $columns[8]
      finality = $columns[9]
    }
    transferGate = [System.Boolean]::Parse($columns[10])
    requiredObservable = $columns[11]
    writeSet = $rowWriteSet
    sourceTheoryHash = $sourceHashListHash
  })
}

$foundationRows = [System.Collections.Generic.List[object]]::new()
foreach ($line in [System.IO.File]::ReadAllLines($foundationKernelFile.FullName)) {
  $columns = $line.Split([char]"`t")
  if ($columns.Count -ne 6) {
    throw "Invalid foundation-model kernel TSV row: $line"
  }
  $foundationRows.Add([ordered]@{
    key = $columns[0]
    input = [ordered]@{ state = $columns[1]; transitionLabel = $columns[2] }
    command = $columns[3]
    outcome = $columns[4]
    targetState = $columns[5]
    sourceTheoryHash = $sourceHashListHash
  })
}

$trustKernelEvidencePath = Join-Path $OutputDirectory 'isabelle-trust-kernel.tsv'
$foundationKernelEvidencePath = Join-Path $OutputDirectory 'isabelle-foundation-kernel.tsv'
Write-Utf8Lf $trustKernelEvidencePath (
  [System.IO.File]::ReadAllText($trustKernelFile.FullName))
Write-Utf8Lf $foundationKernelEvidencePath (
  [System.IO.File]::ReadAllText($foundationKernelFile.FullName))

$trustBody = (($trustRows | ForEach-Object { To-CanonicalJson $_ }) -join "`n") + "`n"
$foundationBody = (($foundationRows | ForEach-Object { To-CanonicalJson $_ }) -join "`n") + "`n"
$trustBodyPath = Join-Path $OutputDirectory 'trust-manifest.body.jsonl'
$foundationBodyPath = Join-Path $OutputDirectory 'foundation-manifest.body.jsonl'
$hashListPath = Join-Path $OutputDirectory 'sha256.tsv'
Write-Utf8Lf $trustBodyPath $trustBody
Write-Utf8Lf $foundationBodyPath $foundationBody
Write-Utf8Lf $hashListPath $hashListText

$trustBodyHash = Get-Sha256File $trustBodyPath
$foundationBodyHash = Get-Sha256File $foundationBodyPath
$combinedManifestHash = Get-Sha256Bytes ($utf8NoBom.GetBytes("$trustBodyHash`n$foundationBodyHash`n"))
$generatorHash = Get-Sha256File $PSCommandPath
$checkerHash = Get-Sha256File $checkerPath
$gitCommit = (& git -C $repoRoot rev-parse HEAD).Trim()

$envelope = [ordered]@{
  schema = 'erc-trust-model-verification-manifest-v1'
  claim = 'mechanically verified regulatory dynamics over the declared domain'
  isabelleVersion = $IsabelleVersion
  repositoryCommit = $gitCommit
  sourceHashListHash = $sourceHashListHash
  generatorHash = $generatorHash
  reverseCheckerHash = $checkerHash
  isabelleKernel = [ordered]@{
    exportCommand = $exportCommand
    trustKernelSha256 = Get-Sha256File $trustKernelEvidencePath
    foundationKernelSha256 = Get-Sha256File $foundationKernelEvidencePath
  }
  trustManifest = [ordered]@{ expectedRows = 18; actualRows = $trustRows.Count; bodySha256 = $trustBodyHash }
  foundationManifest = [ordered]@{ expectedRows = 35; actualRows = $foundationRows.Count; bodySha256 = $foundationBodyHash }
  manifestSha256 = $combinedManifestHash
}
$envelopePath = Join-Path $OutputDirectory 'manifest-envelope.json'
Write-Utf8Lf $envelopePath ((To-CanonicalJson $envelope) + "`n")

Write-Output (To-CanonicalJson ([ordered]@{
  status = 'PASS'
  outputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
  trustRows = $trustRows.Count
  foundationRows = $foundationRows.Count
  sourceHashListHash = $sourceHashListHash
  manifestSha256 = $combinedManifestHash
}))
