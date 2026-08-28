param(
  [Parameter(Mandatory = $true)]
  [string]$IsabelleRoot,
  [Parameter(Mandatory = $true)]
  [string]$AdsFunctor,
  [Parameter(Mandatory = $true)]
  [string]$FormalFoundation
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$sessionDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $sessionDir '..'))
$runId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
$runDirectory = Join-Path $PSScriptRoot "out\runs\$runId"
[System.IO.Directory]::CreateDirectory($runDirectory) | Out-Null

function Get-Sha256File([string]$Path) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([System.BitConverter]::ToString(
      $sha.ComputeHash([System.IO.File]::ReadAllBytes($Path)))).Replace('-', '')
  }
  finally {
    $sha.Dispose()
  }
}

function Write-Utf8Lf([string]$Path, [string]$Text) {
  $normalized = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
  [System.IO.File]::WriteAllText($Path, $normalized, $utf8NoBom)
}

function Convert-ToCygwinPath([string]$WindowsPath) {
  $full = [System.IO.Path]::GetFullPath($WindowsPath)
  $drive = $full.Substring(0, 1).ToLowerInvariant()
  $tail = $full.Substring(2).Replace('\', '/')
  return "/cygdrive/$drive$tail"
}

$trustSources = Get-ChildItem -LiteralPath $sessionDir -Filter '*.thy' -File |
  Sort-Object Name
$bannedPattern = '^\s*(sorry|oops|axiomatization|oracle)\b|\bby\s+eval\b|\bnative_decide\b|\bskip_proof\b'
$bannedMatches = @(
  $trustSources | Select-String -Pattern $bannedPattern -CaseSensitive
)
if ($bannedMatches.Count -ne 0) {
  $details = ($bannedMatches | ForEach-Object {
    "$($_.Path):$($_.LineNumber):$($_.Line.Trim())"
  }) -join "`n"
  throw "Banned proof-trust source forms found:`n$details"
}

$isabelleBash = Join-Path $IsabelleRoot 'contrib\cygwin\bin\bash.exe'
$isabelle = "$(Convert-ToCygwinPath $IsabelleRoot)/bin/isabelle"
$sessionCyg = Convert-ToCygwinPath $sessionDir
$repoCyg = Convert-ToCygwinPath $repoRoot
$adsCyg = Convert-ToCygwinPath $AdsFunctor
$foundationCyg = Convert-ToCygwinPath $FormalFoundation
$buildCommand = "export PATH=/usr/local/bin:/usr/bin:/bin; cd '$repoCyg'; '$isabelle' build -c -o record_proofs=1 -d '$adsCyg' -d '$foundationCyg' -d . ERC_TRUST"
$buildOutput = @(& $isabelleBash --noprofile --norc -c $buildCommand 2>&1)
$buildExitCode = $LASTEXITCODE
$buildLogPath = Join-Path $runDirectory 'isabelle-clean-build.log'
Write-Utf8Lf $buildLogPath (($buildOutput -join "`n") + "`n")

$exportDirectory = Join-Path $runDirectory 'isabelle-export'
$exportCyg = Convert-ToCygwinPath $exportDirectory
$exportCommand = "export PATH=/usr/local/bin:/usr/bin:/bin; '$isabelle' export -d '$adsCyg' -d '$foundationCyg' -d '$repoCyg' -x '*:erc-trust/model-proof-trust.txt' -O '$exportCyg' ERC_TRUST"
$exportOutput = @(& $isabelleBash --noprofile --norc -c $exportCommand 2>&1)
$exportExitCode = $LASTEXITCODE
$exportLogPath = Join-Path $runDirectory 'isabelle-export.log'
Write-Utf8Lf $exportLogPath (($exportOutput -join "`n") + "`n")

$proofAuditFile = if (Test-Path -LiteralPath $exportDirectory) {
  Get-ChildItem -LiteralPath $exportDirectory -Filter 'model-proof-trust.txt' -File -Recurse |
    Select-Object -First 1
} else {
  $null
}
$proofAuditText = if ($null -eq $proofAuditFile) { '' } else {
  [System.IO.File]::ReadAllText($proofAuditFile.FullName)
}
$proofAuditPass =
  $proofAuditText.Contains('status=PASS') -and
  $proofAuditText.Contains('oracle_dependency_count=0')

$report = [ordered]@{
  gate = 'ERC-TRUST-model-proof-closure'
  runId = $runId
  branch = (& git -C $repoRoot branch --show-current).Trim()
  repositoryCommit = (& git -C $repoRoot rev-parse HEAD).Trim()
  dirtyPaths = @(& git -C $repoRoot status --short)
  trustTheoryCount = $trustSources.Count
  bannedSourceForms = $bannedMatches.Count
  build = [ordered]@{
    command = $buildCommand
    exitCode = $buildExitCode
    logSha256 = Get-Sha256File $buildLogPath
  }
  proofAudit = [ordered]@{
    exportCommand = $exportCommand
    exportExitCode = $exportExitCode
    pass = $proofAuditPass
    text = $proofAuditText.Trim()
  }
  status = if ($buildExitCode -eq 0 -and $exportExitCode -eq 0 -and $proofAuditPass) {
    'PASS'
  } else {
    'FAIL'
  }
}
$reportPath = Join-Path $runDirectory 'closure-report.json'
Write-Utf8Lf $reportPath (($report | ConvertTo-Json -Compress -Depth 10) + "`n")

$summary = [ordered]@{
  status = $report.status
  runDirectory = $runDirectory
  buildExitCode = $buildExitCode
  bannedSourceForms = $bannedMatches.Count
  proofAuditPass = $proofAuditPass
  buildLogSha256 = $report.build.logSha256
}
Write-Output ($summary | ConvertTo-Json -Compress)
if ($report.status -ne 'PASS') {
  exit 1
}
