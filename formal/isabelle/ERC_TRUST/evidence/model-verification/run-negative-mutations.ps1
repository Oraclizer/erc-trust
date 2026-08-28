param(
  [Parameter(Mandatory = $true)]
  [string]$IsabelleRoot,
  [Parameter(Mandatory = $true)]
  [string]$AdsFunctor,
  [Parameter(Mandatory = $true)]
  [string]$NodeExecutable,
  [Parameter(Mandatory = $true)]
  [string]$FormalFoundation,
  [string]$TemporaryBaseDirectory = [System.IO.Path]::GetTempPath()
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$sessionDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $sessionDir '..'))
$baselineOut = Join-Path $PSScriptRoot 'out'
$checker = Join-Path $PSScriptRoot 'reverse-check-manifest.mjs'
$baselineEnvelopePath = Join-Path $baselineOut 'manifest-envelope.json'
if (-not (Test-Path -LiteralPath $baselineEnvelopePath)) {
  throw 'Generate the baseline manifest before running mutations'
}
$baselineEnvelope = Get-Content -LiteralPath $baselineEnvelopePath -Raw |
  ConvertFrom-Json
$baselineSourceHashListHash = $baselineEnvelope.sourceHashListHash
$baselineManifestSha256 = $baselineEnvelope.manifestSha256
$runId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
$evidenceDirectory = Join-Path $baselineOut "mutations\$runId"
$temporarySeparators = [char[]]@(
  [System.IO.Path]::DirectorySeparatorChar,
  [System.IO.Path]::AltDirectorySeparatorChar)
$resolvedTemporaryBase = [System.IO.Path]::GetFullPath(
  $TemporaryBaseDirectory).TrimEnd($temporarySeparators)
$temporaryRoot = [System.IO.Path]::GetFullPath(
  (Join-Path $resolvedTemporaryBase "erc-trust-model-mutations-$runId"))

if (
  -not [System.IO.Path]::GetDirectoryName($temporaryRoot).Equals(
    $resolvedTemporaryBase,
    [System.StringComparison]::OrdinalIgnoreCase) -or
  -not [System.IO.Path]::GetFileName($temporaryRoot).StartsWith(
    'erc-trust-model-mutations-',
    [System.StringComparison]::Ordinal)
) {
  throw "Refusing unsafe mutation root: $temporaryRoot"
}
[System.IO.Directory]::CreateDirectory($evidenceDirectory) | Out-Null
[System.IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null

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

function Replace-ExactlyOnce(
  [string]$Path,
  [string]$Before,
  [string]$After
) {
  $text = [System.IO.File]::ReadAllText($Path)
  $lineBreak = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
  $normalizedBefore =
    $Before.Replace("`r`n", "`n").Replace("`r", "`n").Replace(
      "`n", $lineBreak)
  $normalizedAfter =
    $After.Replace("`r`n", "`n").Replace("`r", "`n").Replace(
      "`n", $lineBreak)
  $first =
    $text.IndexOf($normalizedBefore, [System.StringComparison]::Ordinal)
  if ($first -lt 0) {
    throw "Mutation source text not found in $Path"
  }
  $second = $text.IndexOf(
    $normalizedBefore,
    $first + $normalizedBefore.Length,
    [System.StringComparison]::Ordinal)
  if ($second -ge 0) {
    throw "Mutation source text is not unique in $Path"
  }
  $mutated = $text.Substring(0, $first) + $normalizedAfter +
    $text.Substring($first + $normalizedBefore.Length)
  [System.IO.File]::WriteAllText($Path, $mutated, $utf8NoBom)
}

$results = [System.Collections.Generic.List[object]]::new()

function New-ManifestMutationDirectory([string]$Id) {
  $directory = Join-Path $evidenceDirectory $Id
  [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  foreach ($name in @(
      'trust-manifest.body.jsonl',
      'foundation-manifest.body.jsonl',
      'manifest-envelope.json',
      'sha256.tsv',
      'isabelle-trust-kernel.tsv',
      'isabelle-foundation-kernel.tsv')) {
    Copy-Item -LiteralPath (Join-Path $baselineOut $name) `
      -Destination (Join-Path $directory $name)
  }
  return $directory
}

function Invoke-CheckerExpectedFailure([string]$Id, [string]$Directory) {
  $output = @(
    & $NodeExecutable $checker $Directory $IsabelleRoot $AdsFunctor `
      $FormalFoundation 2>&1)
  $exitCode = $LASTEXITCODE
  Write-Utf8Lf (Join-Path $Directory 'checker-console.log') (
    ($output -join "`n") + "`n")
  $script:results.Add([ordered]@{
    id = $Id
    kind = 'manifest'
    expected = 'checker failure'
    exitCode = $exitCode
    killed = ($exitCode -ne 0)
  })
}

$m13Delete = New-ManifestMutationDirectory 'MUT-13-delete-row'
$deletePath = Join-Path $m13Delete 'trust-manifest.body.jsonl'
$deleteLines = [System.IO.File]::ReadAllLines($deletePath)
Write-Utf8Lf $deletePath ((($deleteLines | Select-Object -Skip 1) -join "`n") + "`n")
Invoke-CheckerExpectedFailure 'MUT-13-delete-row' $m13Delete

$m13Duplicate = New-ManifestMutationDirectory 'MUT-13-duplicate-key'
$duplicatePath = Join-Path $m13Duplicate 'trust-manifest.body.jsonl'
$duplicateLines = [System.IO.File]::ReadAllLines($duplicatePath)
Write-Utf8Lf $duplicatePath (
  (($duplicateLines + $duplicateLines[0]) -join "`n") + "`n")
Invoke-CheckerExpectedFailure 'MUT-13-duplicate-key' $m13Duplicate

$m13Outcome = New-ManifestMutationDirectory 'MUT-13-flip-outcome'
$outcomePath = Join-Path $m13Outcome 'trust-manifest.body.jsonl'
$outcomeLines = [System.IO.File]::ReadAllLines($outcomePath)
$outcomeRow = $outcomeLines[0] | ConvertFrom-Json
$outcomeRow.outcome = 'REJECTED'
$outcomeLines[0] = $outcomeRow | ConvertTo-Json -Compress -Depth 20
Write-Utf8Lf $outcomePath (($outcomeLines -join "`n") + "`n")
Invoke-CheckerExpectedFailure 'MUT-13-flip-outcome' $m13Outcome

$m13WriteSet = New-ManifestMutationDirectory 'MUT-13-flip-write-set'
$writeSetPath = Join-Path $m13WriteSet 'trust-manifest.body.jsonl'
$writeSetLines = [System.IO.File]::ReadAllLines($writeSetPath)
$seizeIndex = -1
for ($index = 0; $index -lt $writeSetLines.Length; $index++) {
  if ($writeSetLines[$index].Contains('"key":"TRUST|SEIZE|SUCCESS"')) {
    $seizeIndex = $index
    break
  }
}
if ($seizeIndex -lt 0) {
  throw 'SEIZE success row not found'
}
$writeSetRow = $writeSetLines[$seizeIndex] | ConvertFrom-Json
$writeSetRow.writeSet = @(
  $writeSetRow.writeSet | Where-Object { $_ -ne 'Prior_Holder_Slot' })
$writeSetLines[$seizeIndex] = $writeSetRow | ConvertTo-Json -Compress -Depth 20
Write-Utf8Lf $writeSetPath (($writeSetLines -join "`n") + "`n")
Invoke-CheckerExpectedFailure 'MUT-13-flip-write-set' $m13WriteSet

$isabelleBash = Join-Path $IsabelleRoot 'contrib\cygwin\bin\bash.exe'
$isabelle = "$(Convert-ToCygwinPath $IsabelleRoot)/bin/isabelle"
$adsCyg = Convert-ToCygwinPath $AdsFunctor
$foundationCyg = Convert-ToCygwinPath $FormalFoundation

function Invoke-SourceMutation(
  [string]$Id,
  [string]$RelativeFile,
  [string]$Before,
  [string]$After
) {
  $mutantRepo = Join-Path $temporaryRoot $Id
  $mutantCdsp = Join-Path $mutantRepo 'Cross_Domain_State_Preservation'
  $mutantSession = Join-Path $mutantRepo 'ERC_TRUST'
  [System.IO.Directory]::CreateDirectory($mutantRepo) | Out-Null
  Write-Utf8Lf (Join-Path $mutantRepo 'ROOTS') (
    "Cross_Domain_State_Preservation`nERC_TRUST`n")
  Copy-Item -LiteralPath $FormalFoundation `
    -Destination $mutantCdsp -Recurse
  [System.IO.Directory]::CreateDirectory($mutantSession) | Out-Null
  Copy-Item -LiteralPath (Join-Path $sessionDir 'ROOT') `
    -Destination (Join-Path $mutantSession 'ROOT')
  Copy-Item -LiteralPath (Join-Path $sessionDir 'document') `
    -Destination (Join-Path $mutantSession 'document') -Recurse
  Get-ChildItem -LiteralPath $sessionDir -Filter '*.thy' -File |
    Copy-Item -Destination $mutantSession
  $mutantFile = Join-Path $mutantSession $RelativeFile
  Replace-ExactlyOnce $mutantFile $Before $After
  $mutantRepoCyg = Convert-ToCygwinPath $mutantRepo
  $command = "export PATH=/usr/local/bin:/usr/bin:/bin; cd '$mutantRepoCyg'; '$isabelle' build -c -o record_proofs=1 -d '$adsCyg' -d . ERC_TRUST"
  $output = @(& $isabelleBash --noprofile --norc -c $command 2>&1)
  $exitCode = $LASTEXITCODE
  Write-Utf8Lf (Join-Path $evidenceDirectory "$Id-build.log") (
    ($output -join "`n") + "`n")
  $script:results.Add([ordered]@{
    id = $Id
    kind = 'source'
    expected = 'Isabelle build failure'
    exitCode = $exitCode
    killed = ($exitCode -ne 0)
  })
  $resolvedMutantRepo = [System.IO.Path]::GetFullPath($mutantRepo)
  if (-not $resolvedMutantRepo.StartsWith(
      $temporaryRoot + [System.IO.Path]::DirectorySeparatorChar,
      [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing unsafe mutant cleanup: $resolvedMutantRepo"
  }
  Remove-Item -LiteralPath $resolvedMutantRepo -Recurse -Force
}
Invoke-SourceMutation `
  'MUT-02-success-precondition-false' `
  'Regulatory_Execution_Simulation.thy' `
  'context_module_ready = True,' `
  'context_module_ready = False,'

Invoke-SourceMutation `
  'MUT-04-forbidden-recover-label' `
  'Regulatory_Execution_Semantics.thy' `
  '"rcp_transition_label Legal_Recover = None"' `
  '"rcp_transition_label Legal_Recover = Some RELEASE"'

Invoke-SourceMutation `
  'MUT-05-remove-regulatory-authority-anchor' `
  'Regulatory_Execution_Simulation.thy' `
  'trust_regulatory_authorities = {9},' `
  'trust_regulatory_authorities = {},'

Invoke-SourceMutation `
  'MUT-06-no-nonce-consumption' `
  'Regulatory_Execution_Semantics.thy' `
  'insert (context_nonce ctx) (trust_consumed_nonces st),' `
  'trust_consumed_nonces st,'

Invoke-SourceMutation `
  'MUT-10-drop-prior-holder' `
  'Regulatory_Execution_Semantics.thy' `
  '(context_subject ctx := Some (context_subject ctx))' `
  '(context_subject ctx := None)'

Invoke-SourceMutation `
  'MUT-14-release-keeps-custody' `
  'Regulatory_Execution_Semantics.thy' `
  '| "resulting_custody (Transition_Operation RELEASE) ctx custody =' `
  '| "resulting_custody (Transition_Operation UNRESTRICT) ctx custody ='

Invoke-SourceMutation `
  'MUT-16-governance-bypasses-regulatory-state' `
  'Privileged_Governance.thy' `
  'trust_modes st account = ACTIVE' `
  'trust_modes st account = SEIZED'

Invoke-SourceMutation `
  'MUT-23-governance-no-nonce-consumption' `
  'Privileged_Governance.thy' `
  'insert nonce (trust_consumed_nonces st),' `
  'trust_consumed_nonces st,'

Invoke-SourceMutation `
  'MUT-24-seize-drops-custody' `
  'Regulatory_Execution_Semantics.thy' `
  'custody(context_subject ctx := context_destination ctx)' `
  'custody(context_subject ctx := None)'

$settlementBindingBefore = @'
          trust_settlement_commitment :=
            (if op = RCP_Operation Legal_Liquidate
             then (trust_settlement_commitment st)
                    (context_case ctx :=
                      Some (context_external_commitment ctx))
             else trust_settlement_commitment st),
'@
$settlementBindingAfter = @'
          trust_settlement_commitment := trust_settlement_commitment st,
'@
Invoke-SourceMutation `
  'MUT-25-liquidate-drops-settlement-binding' `
  'Regulatory_Execution_Semantics.thy' `
  $settlementBindingBefore `
  $settlementBindingAfter

Invoke-SourceMutation `
  'MUT-26-recover-does-not-credit-destination' `
  'Regulatory_Execution_Semantics.thy' `
  'trust_balances st destination + context_amount ctx' `
  'trust_balances st destination'

$baselineCyg = Convert-ToCygwinPath $repoRoot
$restoreCommand = "export PATH=/usr/local/bin:/usr/bin:/bin; cd '$baselineCyg'; '$isabelle' build -c -o record_proofs=1 -d '$adsCyg' -d '$foundationCyg' -d . ERC_TRUST"
$restoreOutput = @(& $isabelleBash --noprofile --norc -c $restoreCommand 2>&1)
$restoreExitCode = $LASTEXITCODE
Write-Utf8Lf (Join-Path $evidenceDirectory 'baseline-restore-build.log') (
  ($restoreOutput -join "`n") + "`n")

$resolvedTemporaryRoot = [System.IO.Path]::GetFullPath($temporaryRoot)
if (
  -not [System.IO.Path]::GetDirectoryName($resolvedTemporaryRoot).Equals(
    $resolvedTemporaryBase,
    [System.StringComparison]::OrdinalIgnoreCase) -or
  -not [System.IO.Path]::GetFileName($resolvedTemporaryRoot).StartsWith(
    'erc-trust-model-mutations-',
    [System.StringComparison]::Ordinal)
) {
  throw "Refusing unsafe temporary-root cleanup: $resolvedTemporaryRoot"
}
Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force

$killed = @($results | Where-Object { $_.killed }).Count
$report = [ordered]@{
  gate = 'ERC-TRUST-model-negative-mutation'
  runId = $runId
  baselineSourceHashListHash = $baselineSourceHashListHash
  baselineManifestSha256 = $baselineManifestSha256
  mutationTotal = $results.Count
  mutationKilled = $killed
  baselineRestoreExitCode = $restoreExitCode
  results = $results
  status = if ($killed -eq $results.Count -and $restoreExitCode -eq 0) {
    'PASS'
  } else {
    'FAIL'
  }
}
Write-Utf8Lf (Join-Path $evidenceDirectory 'mutation-report.json') (
  ($report | ConvertTo-Json -Compress -Depth 10) + "`n")
Write-Output ($report | ConvertTo-Json -Compress -Depth 10)
if ($report.status -ne 'PASS') {
  exit 1
}
