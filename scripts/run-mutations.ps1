param(
    [string]$Forge = "forge",
    [string]$Workspace = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$systemTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
if ([string]::IsNullOrWhiteSpace($Workspace)) {
    $Workspace = Join-Path $systemTempRoot "erc-trust-candidate-mutations"
}
$resolvedWorkspace = [System.IO.Path]::GetFullPath($Workspace)
$allowedRoot = $systemTempRoot
if (-not $resolvedWorkspace.StartsWith($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Mutation workspace must remain below the system temporary directory: $resolvedWorkspace"
}
if ([System.IO.Path]::GetPathRoot($resolvedWorkspace) -eq $resolvedWorkspace) {
    throw "Refusing broad mutation workspace: $resolvedWorkspace"
}

$mutations = @(
    @{
        Id = "MUT-01-FROZEN-FLOOR"
        Fault = "Remove both ordinary-transfer frozen-floor checks"
        File = "implementation\src\TrustToken.sol"
        Old = "if (amount > unfrozen) revert ERC7943InsufficientUnfrozenBalance(from, amount, unfrozen);"
        New = "if (false) revert ERC7943InsufficientUnfrozenBalance(from, amount, unfrozen);"
        Old2 = "if (!canTransfer(from, to, amount)) revert ERC7943CannotTransfer(from, to, amount);"
        New2 = "if (false) revert ERC7943CannotTransfer(from, to, amount);"
        Contract = "TrustActionsFuzzTest"
        Test = "testFuzzFreezeAbsoluteAndOrdinaryFloor"
    },
    @{
        Id = "MUT-02-ROUTE-CONSUMPTION"
        Fault = "Keep an ERC-7943 route ticket live after use"
        File = "implementation\src\TrustToken.sol"
        Old = "delete _routeTicket;"
        New = "_routeTicket.live = true;"
        Contract = "TrustActionsUnitTest"
        Test = "testERC7943ExactUseRoutesAndInterfaceTruth"
    },
    @{
        Id = "MUT-03-RECEIPT-LAST"
        Fault = "Emit a base event after the canonical TRUST receipt"
        File = "implementation\src\TrustToken.sol"
        Old = "emit RegulatoryActionApplied(request.actionId, request.action, request.caseId, receiptHash);"
        New = "emit RegulatoryActionApplied(request.actionId, request.action, request.caseId, receiptHash);`r`n        emit Frozen(request.subject, _frozen[request.subject]);"
        Contract = "TrustActionsUnitTest"
        Test = "testCanonicalEventOrder"
    },
    @{
        Id = "MUT-04-FAIL-CLOSED"
        Fault = "Allow OperationalFailure assessment to continue"
        File = "implementation\src\TrustToken.sol"
        Old = "if (outcome == TrustTypes.AssessmentOutcome.OPERATIONAL_FAILURE) {"
        New = "if (false) {"
        Contract = "TrustActionsUnitTest"
        Test = "testRejectedAndOperationalFailureStutter"
    },
    @{
        Id = "MUT-05-FIXED-ACTION"
        Fault = "Remove destination from action-id binding"
        File = "implementation\src\TrustToken.sol"
        Old = "normalized.actionId = bytes32(0);"
        New = "normalized.actionId = bytes32(0);`n        normalized.destination = address(0);"
        Contract = "TrustActionsUnitTest"
        Test = "testReplayFixedActionAndConfiscateTerminality"
    },
    @{
        Id = "MUT-06-NONCE-CONSUMPTION"
        Fault = "Do not consume the action nonce"
        File = "implementation\src\TrustToken.sol"
        Old = "_usedNonces[request.authorityRef][request.authorityEpoch][request.nonce] = true;"
        New = "_usedNonces[request.authorityRef][request.authorityEpoch][request.nonce] = false;"
        Contract = "TrustActionsFuzzTest"
        Test = "testFuzzForcedActionsPreserveSupply"
    },
    @{
        Id = "MUT-07-ERC3643-RAW-BYPASS"
        Fault = "Permit any caller to use ERC-3643 Agent mutators"
        File = "implementation\test\mocks\MockERC3643Token.sol"
        Old = "require(msg.sender == exclusiveAgent && exclusiveAgent != address(0), `"agent`");"
        New = "require(exclusiveAgent != address(0), `"agent`");"
        Contract = "ERC3643ProfileUnitTest"
        Test = "testProfileSealAndDirectBypassClosure"
    },
    @{
        Id = "MUT-08-FREEZE-DIRECTION"
        Fault = "Permit equal or decreasing targets through FREEZE"
        File = "implementation\src\TrustToken.sol"
        Old = "request.amount <= _frozen[request.subject]"
        New = "false"
        Contract = "TrustActionsUnitTest"
        Test = "testFreezeDirectionShapeAndReversalPolicyFailClosed"
    },
    @{
        Id = "MUT-09-CASE-TERMINALITY"
        Fault = "Do not mark a CONFISCATE case terminal"
        File = "implementation\src\TrustToken.sol"
        Old = "_terminalCases[request.caseId] = true;"
        New = "_terminalCases[request.caseId] = false;"
        Contract = "TrustActionsUnitTest"
        Test = "testReplayFixedActionAndConfiscateTerminality"
    },
    @{
        Id = "MUT-10-CUSTODY-CLOSURE"
        Fault = "Skip matched custody closure before disposition"
        File = "implementation\src\TrustToken.sol"
        Old = "if (!custody.active) return false;"
        New = "return false;"
        Contract = "TrustActionsUnitTest"
        Test = "testConfiscateFromCustodyClosesAndTerminatesCase"
    },
    @{
        Id = "MUT-11-REVERSAL-POLICY"
        Fault = "Skip current-policy assessment before direct reversal"
        File = "implementation\src\TrustToken.sol"
        Old = "_assessReversalOrRevert(request, digest);"
        New = ""
        FirstOnly = $true
        Contract = "TrustActionsUnitTest"
        Test = "testFreezeDirectionShapeAndReversalPolicyFailClosed"
    }
)

if (Test-Path -LiteralPath $resolvedWorkspace) {
    $resolvedExisting = (Resolve-Path -LiteralPath $resolvedWorkspace).Path
    if (-not $resolvedExisting.StartsWith($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Resolved mutation workspace escaped the system temporary directory: $resolvedExisting"
    }
    Remove-Item -LiteralPath $resolvedExisting -Recurse -Force
}
New-Item -ItemType Directory -Path $resolvedWorkspace | Out-Null

$results = @()
foreach ($mutation in $mutations) {
    $caseRoot = Join-Path $resolvedWorkspace $mutation.Id
    New-Item -ItemType Directory -Path $caseRoot | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot "foundry.toml") -Destination $caseRoot
    $caseImplementation = Join-Path $caseRoot "implementation"
    New-Item -ItemType Directory -Path $caseImplementation | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot "implementation\src") -Destination $caseImplementation -Recurse
    Copy-Item -LiteralPath (Join-Path $repoRoot "implementation\test") -Destination $caseImplementation -Recurse

    $target = Join-Path $caseRoot $mutation.File
    $content = [System.IO.File]::ReadAllText($target)
    $occurrences = ([regex]::Matches($content, [regex]::Escape($mutation.Old))).Count
    if ($occurrences -lt 1) {
        throw "$($mutation.Id): mutation anchor not found"
    }
    if (
        $mutation.Id -ne "MUT-06-NONCE-CONSUMPTION" -and
        -not $mutation.ContainsKey("FirstOnly") -and
        $occurrences -ne 1
    ) {
        throw "$($mutation.Id): expected one anchor, found $occurrences"
    }
    if ($mutation.Id -eq "MUT-06-NONCE-CONSUMPTION" -or $mutation.ContainsKey("FirstOnly")) {
        $index = $content.IndexOf($mutation.Old)
        $content = $content.Remove($index, $mutation.Old.Length).Insert($index, $mutation.New)
    } else {
        $content = $content.Replace($mutation.Old, $mutation.New)
    }
    if ($mutation.ContainsKey("Old2")) {
        $secondaryOccurrences = ([regex]::Matches($content, [regex]::Escape($mutation.Old2))).Count
        if ($secondaryOccurrences -ne 1) {
            throw "$($mutation.Id): expected one secondary anchor, found $secondaryOccurrences"
        }
        $content = $content.Replace($mutation.Old2, $mutation.New2)
    }
    [System.IO.File]::WriteAllText($target, $content)

    Push-Location $caseRoot
    try {
        & $Forge test --match-contract $mutation.Contract --match-test $mutation.Test --fuzz-runs 64 --silent
        $exitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    $killed = $exitCode -ne 0
    $results += [ordered]@{
        id = $mutation.Id
        fault = $mutation.Fault
        detector = "$($mutation.Contract).$($mutation.Test)"
        result = if ($killed) { "KILLED" } else { "SURVIVED" }
    }
}

$summary = [ordered]@{
    schema = "erc-trust-mutation-result-v1"
    toolchain = [ordered]@{
        forge = "1.7.1"
        solc = "0.8.36"
        fuzzRunsPerMutation = 64
    }
    total = $results.Count
    killed = @($results | Where-Object { $_.result -eq "KILLED" }).Count
    survived = @($results | Where-Object { $_.result -eq "SURVIVED" }).Count
    results = $results
    replay = "powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-mutations.ps1"
    claim = "All declared mutations were killed. This is detector evidence, not an audit or completeness proof."
}
$json = ($summary | ConvertTo-Json -Depth 6) + "`n"
[System.IO.File]::WriteAllText(
    (Join-Path $repoRoot "evidence\mutation-results.json"),
    $json,
    [System.Text.UTF8Encoding]::new($false))
$json
if ($summary.survived -ne 0) {
    exit 1
}
