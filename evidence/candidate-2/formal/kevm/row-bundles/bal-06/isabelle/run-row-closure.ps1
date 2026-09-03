param(
  [Parameter(Mandatory = $true)]
  [string]$OutputDirectory,
  [string]$IsabelleRoot = $env:ISABELLE_ROOT,
  [string]$AdsFunctor = $env:ADS_FUNCTOR_ROOT,
  [string]$FormalFoundation = $env:FORMAL_FOUNDATION_ROOT
)

$ErrorActionPreference = 'Stop'
foreach ($input in @($IsabelleRoot, $AdsFunctor, $FormalFoundation)) {
  if ([string]::IsNullOrWhiteSpace($input)) {
    throw 'Set ISABELLE_ROOT, ADS_FUNCTOR_ROOT, and FORMAL_FOUNDATION_ROOT or pass all three parameters.'
  }
}
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$sessionDir = [System.IO.Path]::GetFullPath($PSScriptRoot)
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $sessionDir '..\..\..\..\..'))
$formalIsabelle = Join-Path $repoRoot 'formal\isabelle'
$theoryPath = Join-Path $sessionDir 'BAL_06_Closure.thy'
$rowManifestPath = Join-Path $repoRoot 'formal\kevm\row-bundles\bal-06\bridge\row-manifest.json'
$outputFull = [System.IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $outputFull) {
  throw "OutputDirectory must be new: $outputFull"
}
[System.IO.Directory]::CreateDirectory($outputFull) | Out-Null

function Convert-ToCygwinPath([string]$WindowsPath) {
  $full = [System.IO.Path]::GetFullPath($WindowsPath)
  $drive = $full.Substring(0, 1).ToLowerInvariant()
  $tail = $full.Substring(2).Replace('\', '/')
  return "/cygdrive/$drive$tail"
}

function Write-Utf8Lf([string]$Path, [string]$Text) {
  $normalized = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
  [System.IO.File]::WriteAllText($Path, $normalized, $utf8NoBom)
}

function Get-Sha256File([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

foreach ($required in @(
  (Join-Path $IsabelleRoot 'contrib\cygwin\bin\bash.exe'),
  (Join-Path $IsabelleRoot 'bin\isabelle'),
  $AdsFunctor,
  $FormalFoundation,
  $formalIsabelle,
  (Join-Path $sessionDir 'ROOT'),
  $theoryPath,
  $rowManifestPath
)) {
  if (-not (Test-Path -LiteralPath $required)) {
    throw "Missing Isabelle input: $required"
  }
}

$theorySources = @(Get-ChildItem -LiteralPath $sessionDir -Filter '*.thy' -File | Sort-Object Name)
$bannedPattern = '^\s*(sorry|oops|axiomatization|oracle)\b|\bby\s+eval\b|\bnative_decide\b|\bskip_proof\b'
$bannedMatches = @($theorySources | Select-String -Pattern $bannedPattern -CaseSensitive)
if ($bannedMatches.Count -ne 0) {
  $details = ($bannedMatches | ForEach-Object { "$($_.Path):$($_.LineNumber):$($_.Line.Trim())" }) -join "`n"
  throw "Banned proof-trust source forms found:`n$details"
}

$cygwinBash = Join-Path $IsabelleRoot 'contrib\cygwin\bin\bash.exe'
$isabelle = "$(Convert-ToCygwinPath $IsabelleRoot)/bin/isabelle"
$adsCyg = Convert-ToCygwinPath $AdsFunctor
$foundationCyg = Convert-ToCygwinPath $FormalFoundation
$formalCyg = Convert-ToCygwinPath $formalIsabelle
$sessionCyg = Convert-ToCygwinPath $sessionDir
$exportDirectory = Join-Path $outputFull 'export'
$exportCyg = Convert-ToCygwinPath $exportDirectory

$buildCommand = "export PATH=/usr/local/bin:/usr/bin:/bin; '$isabelle' build -c -o record_proofs=1 -d '$adsCyg' -d '$foundationCyg' -d '$formalCyg' -d '$sessionCyg' BAL_06_Row"
$savedErrorPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$buildOutput = @(& $cygwinBash --noprofile --norc -c $buildCommand 2>&1)
$buildExit = $LASTEXITCODE
$ErrorActionPreference = $savedErrorPreference
$buildLog = Join-Path $outputFull 'isabelle-build.log'
Write-Utf8Lf $buildLog (($buildOutput -join "`n") + "`n")

$exportCommand = "export PATH=/usr/local/bin:/usr/bin:/bin; '$isabelle' export -d '$adsCyg' -d '$foundationCyg' -d '$formalCyg' -d '$sessionCyg' -x '*:erc-trust/bal-06-proof-trust.txt' -O '$exportCyg' BAL_06_Row"
$ErrorActionPreference = 'Continue'
$exportOutput = @(& $cygwinBash --noprofile --norc -c $exportCommand 2>&1)
$exportExit = $LASTEXITCODE
$ErrorActionPreference = $savedErrorPreference
$exportLog = Join-Path $outputFull 'isabelle-export.log'
Write-Utf8Lf $exportLog (($exportOutput -join "`n") + "`n")

$auditFile = Get-ChildItem -LiteralPath $exportDirectory -Filter 'bal-06-proof-trust.txt' -File -Recurse -ErrorAction SilentlyContinue |
  Select-Object -First 1
$auditText = if ($null -eq $auditFile) { '' } else { [System.IO.File]::ReadAllText($auditFile.FullName) }
$auditPass =
  $auditText.Contains('status=PASS') -and
  $auditText.Contains('theorem_root_count=4') -and
  $auditText.Contains('oracle_dependency_count=0')

$report = [ordered]@{
  schemaVersion = 1
  obligationId = 'BAL-06'
  session = 'BAL_06_Row'
  theoremName = 'ordinary_transfer_preserves_backing_and_own_frozen_floor'
  status = if ($buildExit -eq 0 -and $exportExit -eq 0 -and $bannedMatches.Count -eq 0 -and $auditPass) { 'PASS' } else { 'FAIL' }
  outputDirectory = $outputFull
  theoryCount = $theorySources.Count
  bannedSourceForms = $bannedMatches.Count
  buildExitCode = $buildExit
  exportExitCode = $exportExit
  oracleDependencyCount = if ($auditPass) { 0 } else { $null }
  theorySha256 = Get-Sha256File $theoryPath
  rowManifestSha256 = Get-Sha256File $rowManifestPath
  build = [ordered]@{
    command = $buildCommand
    exitCode = $buildExit
    logSha256 = Get-Sha256File $buildLog
  }
  proofAudit = [ordered]@{
    command = $exportCommand
    exitCode = $exportExit
    pass = $auditPass
    text = $auditText.Trim()
  }
}
$reportPath = Join-Path $outputFull 'report.json'
Write-Utf8Lf $reportPath (($report | ConvertTo-Json -Depth 10) + "`n")
Write-Output (($report | ConvertTo-Json -Compress -Depth 10))
if ($report.status -ne 'PASS') { exit 1 }
