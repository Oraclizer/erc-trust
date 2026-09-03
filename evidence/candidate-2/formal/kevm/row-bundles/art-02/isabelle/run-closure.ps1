[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$IsabelleRoot,
  [Parameter(Mandatory = $true)]
  [string]$AdsFunctor,
  [Parameter(Mandatory = $true)]
  [string]$FormalFoundation,
  [Parameter(Mandatory = $true)]
  [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$rowDirectory = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$rowIsabelleDirectory = [System.IO.Path]::GetFullPath($PSScriptRoot)
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $rowDirectory '..\..\..\..'))
$ercTrustDirectory = Join-Path $repositoryRoot 'formal\isabelle\ERC_TRUST'
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
[System.IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null

function Convert-ToCygwinPath([string]$WindowsPath) {
  $full = [System.IO.Path]::GetFullPath($WindowsPath)
  if ($full -notmatch '^([A-Za-z]):\\(.*)$') {
    throw "cannot convert path to Cygwin form: $full"
  }
  $drive = $Matches[1].ToLowerInvariant()
  $tail = $Matches[2].Replace('\', '/')
  return "/cygdrive/$drive/$tail"
}

function Get-Sha256File([string]$Path) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([System.BitConverter]::ToString(
      $sha.ComputeHash([System.IO.File]::ReadAllBytes($Path)))).Replace('-', '').ToLowerInvariant()
  }
  finally {
    $sha.Dispose()
  }
}

function Write-Utf8Lf([string]$Path, [string]$Text) {
  $normalized = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
  [System.IO.File]::WriteAllText($Path, $normalized, $utf8NoBom)
}

$theoryPath = Join-Path $rowIsabelleDirectory 'ART_02_Compiler_Output_Runtime_Binding.thy'
$rowManifestPath = Join-Path $rowDirectory 'bridge\row-manifest.json'
$bannedPattern = '^\s*(sorry|oops|axiomatization|oracle)\b|\bby\s+eval\b|\bnative_decide\b|\bskip_proof\b'
$bannedMatches = @(Select-String -LiteralPath $theoryPath -Pattern $bannedPattern -CaseSensitive)
if ($bannedMatches.Count -ne 0) {
  throw "Banned proof-trust source forms found in $theoryPath"
}

$isabelleBash = Join-Path $IsabelleRoot 'contrib\cygwin\bin\bash.exe'
if (-not (Test-Path -LiteralPath $isabelleBash -PathType Leaf)) {
  throw "Isabelle bash not found: $isabelleBash"
}
$isabelle = "$(Convert-ToCygwinPath $IsabelleRoot)/bin/isabelle"
$repositoryCyg = Convert-ToCygwinPath $repositoryRoot
$adsCyg = Convert-ToCygwinPath $AdsFunctor
$foundationCyg = Convert-ToCygwinPath $FormalFoundation
$ercTrustCyg = Convert-ToCygwinPath $ercTrustDirectory
$rowIsabelleCyg = Convert-ToCygwinPath $rowIsabelleDirectory
$outputCyg = Convert-ToCygwinPath $OutputDirectory

$buildCommand = "export PATH=/usr/local/bin:/usr/bin:/bin; cd '$repositoryCyg'; '$isabelle' build -c -o record_proofs=1 -d '$adsCyg' -d '$foundationCyg' -d '$ercTrustCyg' -d '$rowIsabelleCyg' ERC_TRUST_ART_02"
$buildOutput = @(& $isabelleBash --noprofile --norc -c $buildCommand 2>&1)
$buildExitCode = $LASTEXITCODE
$buildLogPath = Join-Path $OutputDirectory 'isabelle-clean-build.log'
Write-Utf8Lf $buildLogPath (($buildOutput -join "`n") + "`n")
if ($buildExitCode -ne 0) {
  throw "Isabelle build failed with exit code $buildExitCode; see $buildLogPath"
}

$exportDirectory = Join-Path $OutputDirectory 'isabelle-export'
[System.IO.Directory]::CreateDirectory($exportDirectory) | Out-Null
$exportCyg = Convert-ToCygwinPath $exportDirectory
$exportCommand = "export PATH=/usr/local/bin:/usr/bin:/bin; '$isabelle' export -d '$adsCyg' -d '$foundationCyg' -d '$ercTrustCyg' -d '$rowIsabelleCyg' -x '*:erc-trust-art-02/proof-trust.txt' -O '$exportCyg' ERC_TRUST_ART_02"
$exportOutput = @(& $isabelleBash --noprofile --norc -c $exportCommand 2>&1)
$exportExitCode = $LASTEXITCODE
$exportLogPath = Join-Path $OutputDirectory 'isabelle-export.log'
Write-Utf8Lf $exportLogPath (($exportOutput -join "`n") + "`n")
if ($exportExitCode -ne 0) {
  throw "Isabelle export failed with exit code $exportExitCode; see $exportLogPath"
}

$proofAuditFile = Get-ChildItem -LiteralPath $exportDirectory -Filter 'proof-trust.txt' -File -Recurse |
  Select-Object -First 1
if ($null -eq $proofAuditFile) {
  throw 'ART-02 proof-trust export is missing'
}
$proofAuditText = [System.IO.File]::ReadAllText($proofAuditFile.FullName)
$qualifiedTheorem = 'ART_02_Compiler_Output_Runtime_Binding.compiler_output_runtime_bytes_are_hash_bound'
$proofAuditPass =
  $proofAuditText.Contains('status=PASS') -and
  $proofAuditText.Contains("qualified_theorem=$qualifiedTheorem") -and
  $proofAuditText.Contains('oracle_dependency_count=0')
if (-not $proofAuditPass) {
  throw "ART-02 proof-trust export failed validation: $proofAuditText"
}

$report = [ordered]@{
  status = 'PASS'
  session = 'ERC_TRUST_ART_02'
  theoremName = 'compiler_output_runtime_bytes_are_hash_bound'
  buildExitCode = $buildExitCode
  exportExitCode = $exportExitCode
  bannedSourceForms = $bannedMatches.Count
  oracleDependencyCount = 0
  buildLogSha256 = Get-Sha256File $buildLogPath
  theorySha256 = Get-Sha256File $theoryPath
  rowManifestSha256 = Get-Sha256File $rowManifestPath
}
$reportPath = Join-Path $OutputDirectory 'closure-report.json'
Write-Utf8Lf $reportPath (($report | ConvertTo-Json -Depth 10) + "`n")
Write-Output ($report | ConvertTo-Json -Compress)
