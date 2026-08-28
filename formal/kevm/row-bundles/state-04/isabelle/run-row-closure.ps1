param(
  [Parameter(Mandatory = $true)] [string]$OutputDirectory,
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
$outputFull = [System.IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $outputFull) { throw "OutputDirectory must be new: $outputFull" }
[System.IO.Directory]::CreateDirectory($outputFull) | Out-Null
function Convert-ToCygwinPath([string]$path) { $full=[System.IO.Path]::GetFullPath($path); return "/cygdrive/$($full.Substring(0,1).ToLowerInvariant())$($full.Substring(2).Replace('\','/'))" }
function Write-Utf8Lf([string]$path,[string]$text) { [System.IO.File]::WriteAllText($path,$text.Replace("`r`n","`n").Replace("`r","`n"),$utf8NoBom) }
function Get-Sha256File([string]$path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
foreach ($required in @((Join-Path $IsabelleRoot 'contrib\cygwin\bin\bash.exe'),(Join-Path $IsabelleRoot 'bin\isabelle'),$AdsFunctor,$FormalFoundation,$formalIsabelle,(Join-Path $sessionDir 'ROOT'))) { if(-not (Test-Path -LiteralPath $required)){throw "Missing Isabelle input: $required"} }
$sources=@(Get-ChildItem -LiteralPath $sessionDir -Filter '*.thy' -File | Sort-Object Name)
$closureTheory=Join-Path $sessionDir 'STATE_04_Closure.thy'; $rowManifest=Join-Path $repoRoot 'formal\kevm\row-bundles\state-04\bridge\row-manifest.json'
foreach($requiredRowInput in @($closureTheory,$rowManifest)){if(-not (Test-Path -LiteralPath $requiredRowInput)){throw "Missing STATE-04 row input: $requiredRowInput"}}
$banned='^\s*(sorry|oops|axiomatization|oracle)\b|\bby\s+eval\b|\bnative_decide\b|\bskip_proof\b'
$bannedMatches=@($sources|Select-String -Pattern $banned -CaseSensitive)
if($bannedMatches.Count -ne 0){throw "Banned proof-trust source forms found"}
$bash=Join-Path $IsabelleRoot 'contrib\cygwin\bin\bash.exe'; $isabelle="$(Convert-ToCygwinPath $IsabelleRoot)/bin/isabelle"; $ads=Convert-ToCygwinPath $AdsFunctor; $foundation=Convert-ToCygwinPath $FormalFoundation; $formal=Convert-ToCygwinPath $formalIsabelle; $session=Convert-ToCygwinPath $sessionDir; $exportDirectory=Join-Path $outputFull 'export'; $export=Convert-ToCygwinPath $exportDirectory
$buildCommand="export PATH=/usr/local/bin:/usr/bin:/bin; '$isabelle' build -c -o record_proofs=1 -d '$ads' -d '$foundation' -d '$formal' -d '$session' STATE_04_Row"
$ErrorActionPreference='Continue'; $buildOutput=@(& $bash --noprofile --norc -c $buildCommand 2>&1); $buildExit=$LASTEXITCODE; $ErrorActionPreference='Stop'; $buildLog=Join-Path $outputFull 'isabelle-build.log'; Write-Utf8Lf $buildLog (($buildOutput -join "`n")+"`n")
$exportCommand="export PATH=/usr/local/bin:/usr/bin:/bin; '$isabelle' export -d '$ads' -d '$foundation' -d '$formal' -d '$session' -x '*:erc-trust/state-04-proof-trust.txt' -O '$export' STATE_04_Row"
$ErrorActionPreference='Continue'; $exportOutput=@(& $bash --noprofile --norc -c $exportCommand 2>&1); $exportExit=$LASTEXITCODE; $ErrorActionPreference='Stop'; $exportLog=Join-Path $outputFull 'isabelle-export.log'; Write-Utf8Lf $exportLog (($exportOutput -join "`n")+"`n")
$auditFile=Get-ChildItem -LiteralPath $exportDirectory -Filter 'state-04-proof-trust.txt' -File -Recurse -ErrorAction SilentlyContinue|Select-Object -First 1; $auditText=if($null -eq $auditFile){''}else{[System.IO.File]::ReadAllText($auditFile.FullName)}; $auditPass=$auditText.Contains('status=PASS') -and $auditText.Contains('theorem_root_count=4') -and $auditText.Contains('oracle_dependency_count=0')
$report=[ordered]@{schemaVersion=1;obligationId='STATE-04';session='STATE_04_Row';theoremName='freeze_and_restriction_are_independent';status=if($buildExit -eq 0 -and $exportExit -eq 0 -and $auditPass){'PASS'}else{'FAIL'};outputDirectory=$outputFull;theoryCount=$sources.Count;bannedSourceForms=$bannedMatches.Count;buildExitCode=$buildExit;exportExitCode=$exportExit;oracleDependencyCount=if($auditPass){0}else{$null};theorySha256=Get-Sha256File $closureTheory;rowManifestSha256=Get-Sha256File $rowManifest;build=[ordered]@{command=$buildCommand;exitCode=$buildExit;logSha256=Get-Sha256File $buildLog};proofAudit=[ordered]@{command=$exportCommand;exitCode=$exportExit;pass=$auditPass;text=$auditText.Trim()}}
$reportPath=Join-Path $outputFull 'report.json'; Write-Utf8Lf $reportPath (($report|ConvertTo-Json -Depth 10)+"`n"); Write-Output ($report|ConvertTo-Json -Compress -Depth 10); if($report.status -ne 'PASS'){exit 1}
