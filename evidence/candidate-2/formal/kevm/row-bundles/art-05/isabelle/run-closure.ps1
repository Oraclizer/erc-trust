[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string]$IsabelleRoot,
  [Parameter(Mandatory = $true)] [string]$AdsFunctor,
  [Parameter(Mandatory = $true)] [string]$FormalFoundation,
  [Parameter(Mandatory = $true)] [string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$rowDirectory = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $rowDirectory '..\..\..\..'))
$ercTrustDirectory = Join-Path $repositoryRoot 'formal\isabelle\ERC_TRUST'
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
[System.IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
function Convert-ToCygwinPath([string]$WindowsPath) {
  $full = [System.IO.Path]::GetFullPath($WindowsPath)
  if ($full -notmatch '^([A-Za-z]):\\(.*)$') { throw "cannot convert path: $full" }
  return "/cygdrive/$($Matches[1].ToLowerInvariant())/$($Matches[2].Replace('\', '/'))"
}
function Get-Sha256File([string]$Path) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { return ([System.BitConverter]::ToString($sha.ComputeHash([System.IO.File]::ReadAllBytes($Path)))).Replace('-', '').ToLowerInvariant() }
  finally { $sha.Dispose() }
}
function Write-Utf8Lf([string]$Path, [string]$Text) { [System.IO.File]::WriteAllText($Path, $Text.Replace("`r`n", "`n").Replace("`r", "`n"), $utf8NoBom) }
$theoryPath = Join-Path $PSScriptRoot 'ART_05_Theory_Import_Closure_Binding.thy'
$rowManifestPath = Join-Path $rowDirectory 'bridge\row-manifest.json'
$banned = @(Select-String -LiteralPath $theoryPath -Pattern '^\s*(sorry|oops|axiomatization|oracle)\b|\bby\s+eval\b|\bnative_decide\b|\bskip_proof\b' -CaseSensitive)
if ($banned.Count -ne 0) { throw 'banned proof-trust source form' }
$bash = Join-Path $IsabelleRoot 'contrib\cygwin\bin\bash.exe'
if (-not (Test-Path -LiteralPath $bash -PathType Leaf)) { throw "Isabelle bash not found: $bash" }
$isabelle = "$(Convert-ToCygwinPath $IsabelleRoot)/bin/isabelle"
$ads = Convert-ToCygwinPath $AdsFunctor; $foundation = Convert-ToCygwinPath $FormalFoundation
$erc = Convert-ToCygwinPath $ercTrustDirectory; $row = Convert-ToCygwinPath $PSScriptRoot; $out = Convert-ToCygwinPath $OutputDirectory
$command = "export PATH=/usr/local/bin:/usr/bin:/bin; '$isabelle' build -c -j 1 -o record_proofs=1 -d '$ads' -d '$foundation' -d '$erc' -d '$row' ERC_TRUST_ART_05"
$build = @(& $bash --noprofile --norc -c $command 2>&1); $buildExit = $LASTEXITCODE
$buildLog = Join-Path $OutputDirectory 'isabelle-clean-build.log'; Write-Utf8Lf $buildLog (($build -join "`n") + "`n")
if ($buildExit -ne 0) { throw "Isabelle build failed: $buildExit" }
$exportDir = Join-Path $OutputDirectory 'isabelle-export'; [System.IO.Directory]::CreateDirectory($exportDir) | Out-Null
$export = Convert-ToCygwinPath $exportDir
$command = "export PATH=/usr/local/bin:/usr/bin:/bin; '$isabelle' export -d '$ads' -d '$foundation' -d '$erc' -d '$row' -x '*:erc-trust-art-05/proof-trust.txt' -O '$export' ERC_TRUST_ART_05"
$exportOutput = @(& $bash --noprofile --norc -c $command 2>&1); $exportExit = $LASTEXITCODE
Write-Utf8Lf (Join-Path $OutputDirectory 'isabelle-export.log') (($exportOutput -join "`n") + "`n")
if ($exportExit -ne 0) { throw "Isabelle export failed: $exportExit" }
$audit = Get-ChildItem -LiteralPath $exportDir -Filter 'proof-trust.txt' -File -Recurse | Select-Object -First 1
if ($null -eq $audit) { throw 'ART-05 proof-trust export missing' }
$auditText = [System.IO.File]::ReadAllText($audit.FullName)
$qualified = 'ART_05_Theory_Import_Closure_Binding.theory_source_and_import_closure_are_hash_bound'
if (-not ($auditText.Contains('status=PASS') -and $auditText.Contains("qualified_theorem=$qualified") -and $auditText.Contains('oracle_dependency_count=0'))) { throw 'ART-05 proof audit failed' }
$report = [ordered]@{ status='PASS'; session='ERC_TRUST_ART_05'; theoremName='theory_source_and_import_closure_are_hash_bound'; buildExitCode=$buildExit; exportExitCode=$exportExit; bannedSourceForms=$banned.Count; oracleDependencyCount=0; buildLogSha256=Get-Sha256File $buildLog; theorySha256=Get-Sha256File $theoryPath; rowManifestSha256=Get-Sha256File $rowManifestPath }
Write-Utf8Lf (Join-Path $OutputDirectory 'closure-report.json') (($report | ConvertTo-Json -Depth 10) + "`n")
Write-Output ($report | ConvertTo-Json -Compress)
