param(
  [string]$Forge = 'forge',
  [string]$Workspace = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$pilotRoot = Join-Path $repoRoot 'pilot'
$systemTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
if ([string]::IsNullOrWhiteSpace($Workspace)) {
  $Workspace = Join-Path $systemTempRoot 'erc-trust-pilot-mutations'
}
$resolvedWorkspace = [System.IO.Path]::GetFullPath($Workspace)
$allowedRoot = $systemTempRoot
if (
  -not $resolvedWorkspace.StartsWith(
    $allowedRoot,
    [System.StringComparison]::OrdinalIgnoreCase) -or
  [System.IO.Path]::GetPathRoot($resolvedWorkspace) -eq $resolvedWorkspace
) {
  throw "Refusing unsafe pilot mutation workspace: $resolvedWorkspace"
}

function Reset-Workspace {
  if (Test-Path -LiteralPath $resolvedWorkspace) {
    Remove-Item -LiteralPath $resolvedWorkspace -Recurse -Force
  }
  [System.IO.Directory]::CreateDirectory($resolvedWorkspace) | Out-Null
  Copy-Item -LiteralPath (Join-Path $pilotRoot 'foundry.toml') `
    -Destination (Join-Path $resolvedWorkspace 'foundry.toml')
  foreach ($directory in @('src', 'test')) {
    Copy-Item -LiteralPath (Join-Path $pilotRoot $directory) `
      -Destination (Join-Path $resolvedWorkspace $directory) -Recurse
  }
}

function Replace-ExactlyOnce(
  [string]$Path,
  [string]$Before,
  [string]$After
) {
  $text = [System.IO.File]::ReadAllText($Path)
  $lineBreak = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
  $normalizedBefore = $Before.Replace("`r`n", "`n").Replace(
    "`r", "`n").Replace("`n", $lineBreak)
  $normalizedAfter = $After.Replace("`r`n", "`n").Replace(
    "`r", "`n").Replace("`n", $lineBreak)
  $first = $text.IndexOf(
    $normalizedBefore,
    [System.StringComparison]::Ordinal)
  if ($first -lt 0) {
    throw "Mutation source text not found: $Path"
  }
  if ($text.IndexOf(
      $normalizedBefore,
      $first + $normalizedBefore.Length,
      [System.StringComparison]::Ordinal) -ge 0) {
    throw "Mutation source text is not unique: $Path"
  }
  $mutated = $text.Substring(0, $first) + $normalizedAfter +
    $text.Substring($first + $normalizedBefore.Length)
  [System.IO.File]::WriteAllText(
    $Path,
    $mutated,
    [System.Text.UTF8Encoding]::new($false))
}

$mutations = @(
  [ordered]@{
    id = 'PILOT-MUT-01-FROZEN-FLOOR'
    before = '        return amount <= available;'
    after = '        return true;'
    test = 'testOrdinaryTransferCannotSpendFrozenAmount'
  },
  [ordered]@{
    id = 'PILOT-MUT-02-ROUTE-CONSUMPTION'
    before = '        delete _routeAuthorizations[routeKey];'
    after = '        _routeAuthorizations[routeKey] = authorizationId;'
    test = 'testStagedSetFrozenConsumesExactTicketAndOrdersLogs'
  },
  [ordered]@{
    id = 'PILOT-MUT-03-RECEIPT-ORDER'
    before = @'
        emit Frozen(execution.subject, execution.targetFrozenAmount);
        emit RegulatoryActionApplied(
            execution.actionId,
            execution.caseId,
            ActionKind.FREEZE,
            execution.source,
            execution.destination,
            execution.targetFrozenAmount,
            execution.authorizationId,
            execution.authorityRef,
            execution.policyBindingHash,
            execution.provenanceHash,
            preObservationHash,
            postObservationHash,
            receiptHash
        );
'@
    after = @'
        emit RegulatoryActionApplied(
            execution.actionId,
            execution.caseId,
            ActionKind.FREEZE,
            execution.source,
            execution.destination,
            execution.targetFrozenAmount,
            execution.authorizationId,
            execution.authorityRef,
            execution.policyBindingHash,
            execution.provenanceHash,
            preObservationHash,
            postObservationHash,
            receiptHash
        );
        emit Frozen(execution.subject, execution.targetFrozenAmount);
'@
    test = 'testStagedSetFrozenConsumesExactTicketAndOrdersLogs'
  },
  [ordered]@{
    id = 'PILOT-MUT-04-ROUTE-BINDING'
    before = @'
        return computeRouteKey(
            actor,
            IERC7943FreezePilot.setFrozenTokens.selector,
            calldataHash,
'@
    after = @'
        return computeRouteKey(
            address(0),
            IERC7943FreezePilot.setFrozenTokens.selector,
            bytes32(0),
'@
    secondBefore = '                || prepared.actor != msg.sender'
    secondAfter = ''
    test = 'testWrongCallerAndCalldataMismatchStutter'
  },
  [ordered]@{
    id = 'PILOT-MUT-05-FAIL-CLOSED'
    before = @'
        if (assessment.outcome == AssessmentOutcome.OPERATIONAL_FAILURE) {
            revert TrustOperationalFailure(commandId, assessment.reason, assessment.dependencyRef);
        }
'@
    after = @'
        if (assessment.outcome == AssessmentOutcome.OPERATIONAL_FAILURE) {
            return;
        }
'@
    test = 'testPolicyRejectAndFailuresStutter'
  }
)

$results = [System.Collections.Generic.List[object]]::new()
foreach ($mutation in $mutations) {
  Reset-Workspace
  $source = Join-Path $resolvedWorkspace 'src\TrustFreezePilot.sol'
  Replace-ExactlyOnce $source $mutation.before $mutation.after
  if ($mutation.Contains('secondBefore')) {
    Replace-ExactlyOnce $source $mutation.secondBefore $mutation.secondAfter
  }

  $previousErrorAction = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $output = @(
    & $Forge test --root $resolvedWorkspace `
      --match-contract TrustFreezePilotTest `
      --match-test $mutation.test 2>&1)
  $exitCode = $LASTEXITCODE
  $ErrorActionPreference = $previousErrorAction
  $results.Add([ordered]@{
    id = $mutation.id
    detector = "TrustFreezePilotTest.$($mutation.test)"
    result = if ($exitCode -ne 0) { 'KILLED' } else { 'SURVIVED' }
    exitCode = $exitCode
  })
}

$killed = @($results | Where-Object { $_.result -eq 'KILLED' }).Count
$result = [ordered]@{
  schema = 'erc-trust-pilot-mutation-result-v1'
  total = $results.Count
  killed = $killed
  survived = $results.Count - $killed
  results = $results
  claim = 'Regression replay for the unchanged preserved pilot; not reference-candidate evidence.'
}
$outputPath = Join-Path $repoRoot 'evidence\pilot-mutation-results.json'
[System.IO.File]::WriteAllText(
  $outputPath,
  (($result | ConvertTo-Json -Depth 10) + "`n"),
  [System.Text.UTF8Encoding]::new($false))

if ($killed -ne $results.Count) {
  throw "Pilot mutation campaign failed: $killed/$($results.Count) killed"
}
Write-Output ($result | ConvertTo-Json -Depth 10)
