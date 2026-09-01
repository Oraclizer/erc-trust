param(
    [string]$Forge = "forge",
    [string]$Workspace = "",
    [string]$OutputPath = "",
    [switch]$PreflightOnly,
    [switch]$UseWslForge
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repoRoot "evidence\mutation-results.json"
}
$systemTempRoot = (Resolve-Path -LiteralPath ([System.IO.Path]::GetTempPath())).Path
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
        Fault = "Ignore the shared ordinary-transfer frozen floor"
        File = "implementation\src\TrustToken.sol"
        Old = "return frozen >= ownPhysical ? 0 : ownPhysical - frozen;"
        New = "return ownPhysical;"
        ExpectedOccurrences = 1
        Contract = "TrustActionsFuzzTest"
        Test = "testFuzzFreezeAbsoluteAndOrdinaryFloor"
    },
    @{
        Id = "MUT-02-ROUTE-CONSUMPTION"
        Fault = "Keep an ERC-7943 route ticket live after use"
        File = "implementation\src\TrustToken.sol"
        Old = "delete _routeTicket;"
        New = "_routeTicket.live = true;"
        ExpectedOccurrences = 1
        Contract = "TrustActionsUnitTest"
        Test = "testERC7943ExactUseRoutesAndInterfaceTruth"
    },
    @{
        Id = "MUT-03-RECEIPT-LAST"
        Fault = "Emit a base event after the canonical TRUST receipt"
        File = "implementation\src\TrustToken.sol"
        Old = "emit RegulatoryActionApplied(request.actionId, request.action, request.caseId, receiptHash);"
        New = "emit RegulatoryActionApplied(request.actionId, request.action, request.caseId, receiptHash);`r`n        emit Frozen(request.subject, _frozen[request.subject]);"
        ExpectedOccurrences = 1
        Contract = "TrustActionsUnitTest"
        Test = "testCanonicalEventOrder"
    },
    @{
        Id = "MUT-04-FAIL-CLOSED"
        Fault = "Allow OperationalFailure assessment to continue"
        File = "implementation\src\TrustToken.sol"
        Old = "if (outcome == TrustTypes.AssessmentOutcome.OPERATIONAL_FAILURE) {"
        New = "if (false) {"
        ExpectedOccurrences = 1
        Contract = "TrustActionsUnitTest"
        Test = "testRejectedAndOperationalFailureStutter"
    },
    @{
        Id = "MUT-05-FIXED-ACTION"
        Fault = "Remove destination from action-id binding"
        File = "implementation\src\TrustToken.sol"
        Old = "calldatacopy(add(ptr, 0x60), request, 0x2a0)`n            if clearId { mstore(add(ptr, 0x80), 0) }"
        New = "calldatacopy(add(ptr, 0x60), request, 0x2a0)`n            if clearId {`n                mstore(add(ptr, 0x80), 0)`n                mstore(add(ptr, 0x100), 0)`n            }"
        ExpectedOccurrences = 1
        Contract = "TrustActionsUnitTest"
        Test = "testReplayFixedActionAndConfiscateTerminality"
    },
    @{
        Id = "MUT-06-NONCE-CONSUMPTION"
        Fault = "Do not consume the action nonce"
        File = "implementation\src\TrustToken.sol"
        Old = "_usedNonces[request.authorityRef][request.authorityEpoch][request.nonce] = true;"
        New = "_usedNonces[request.authorityRef][request.authorityEpoch][request.nonce] = false;"
        ExpectedOccurrences = 2
        FirstOnly = $true
        Contract = "TrustActionsFuzzTest"
        Test = "testFuzzForcedActionsPreserveSupply"
    },
    @{
        Id = "MUT-07-ERC3643-RAW-BYPASS"
        Fault = "Permit any caller to use ERC-3643 Agent mutators"
        File = "implementation\test\mocks\MockERC3643Token.sol"
        Old = "require(msg.sender == exclusiveAgent && exclusiveAgent != address(0), `"agent`");"
        New = "require(exclusiveAgent != address(0), `"agent`");"
        ExpectedOccurrences = 1
        Contract = "ERC3643ProfileUnitTest"
        Test = "testProfileSealAndDirectBypassClosure"
    },
    @{
        Id = "MUT-08-FREEZE-DIRECTION"
        Fault = "Permit equal or decreasing targets through FREEZE"
        File = "implementation\src\TrustToken.sol"
        Old = "request.amount <= _frozen[request.subject]"
        New = "false"
        ExpectedOccurrences = 1
        Contract = "TrustActionsUnitTest"
        Test = "testFreezeDirectionShapeAndReversalPolicyFailClosed"
    },
    @{
        Id = "MUT-09-CASE-TERMINALITY"
        Fault = "Do not mark a CONFISCATE case terminal"
        File = "implementation\src\TrustToken.sol"
        Old = "_terminalCases[request.caseId] = true;"
        New = "_terminalCases[request.caseId] = false;"
        ExpectedOccurrences = 1
        Contract = "TrustActionsUnitTest"
        Test = "testReplayFixedActionAndConfiscateTerminality"
    },
    @{
        Id = "MUT-10-CUSTODY-CLOSURE"
        Fault = "Skip matched custody closure before disposition"
        File = "implementation\src\TrustToken.sol"
        Old = "if (!custody.active) return false;"
        New = "return false;"
        ExpectedOccurrences = 1
        Contract = "TrustActionsUnitTest"
        Test = "testConfiscateFromCustodyClosesAndTerminatesCase"
    },
    @{
        Id = "MUT-11-REVERSAL-POLICY"
        Fault = "Skip current-policy assessment before direct reversal"
        File = "implementation\src\TrustToken.sol"
        Old = "_assessReversalOrRevert(request, digest);"
        New = ""
        ExpectedOccurrences = 2
        FirstOnly = $true
        Contract = "TrustActionsUnitTest"
        Test = "testFreezeDirectionShapeAndReversalPolicyFailClosed"
    },
    @{
        Id = "MUT-12-ERC3643-FREEZE-DIRECTION"
        Fault = "Permit equal or decreasing targets through the ERC-3643 profile"
        File = "implementation\src\profiles\ERC3643TrustAdapter.sol"
        Old = "request.amount <= _frozenTargets[request.subject]"
        New = "false"
        ExpectedOccurrences = 1
        Contract = "ERC3643ProfileUnitTest"
        Test = "testAllSixActionsAndReversals"
    }
)

function Get-TextOccurrences([string]$Content, [string]$Needle) {
    return ([regex]::Matches($Content, [regex]::Escape($Needle))).Count
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-Sha256Bytes([byte[]]$Bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Invoke-Forge([string[]]$Arguments) {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        if ($UseWslForge) {
            Get-Command wsl.exe -CommandType Application -ErrorAction Stop | Out-Null
            $output = @(& wsl.exe -d Ubuntu -e /usr/bin/env NO_COLOR=1 /usr/local/bin/forge @Arguments 2>&1)
        } else {
            Get-Command $Forge -CommandType Application -ErrorAction Stop | Out-Null
            $output = @(& $Forge @Arguments 2>&1)
        }
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    return [PSCustomObject]@{
        Output = [string[]]$output
        ExitCode = $exitCode
    }
}

$testSourceFiles = Get-ChildItem -LiteralPath (Join-Path $repoRoot "implementation\test") -Filter "*.sol" -Recurse

foreach ($mutation in $mutations) {
    $target = Join-Path $repoRoot $mutation.File
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
        throw "$($mutation.Id): target file missing: $($mutation.File)"
    }
    $content = [System.IO.File]::ReadAllText($target)
    $occurrences = Get-TextOccurrences $content $mutation.Old
    if ($occurrences -ne $mutation.ExpectedOccurrences) {
        throw "$($mutation.Id): expected $($mutation.ExpectedOccurrences) primary anchors, found $occurrences"
    }
    if ($mutation.ContainsKey("Old2")) {
        $secondaryOccurrences = Get-TextOccurrences $content $mutation.Old2
        if ($secondaryOccurrences -ne $mutation.ExpectedSecondaryOccurrences) {
            throw "$($mutation.Id): expected $($mutation.ExpectedSecondaryOccurrences) secondary anchors, found $secondaryOccurrences"
        }
    }
    $contractPattern = "contract\s+$([regex]::Escape($mutation.Contract))\b"
    $contractFiles = @($testSourceFiles | Where-Object {
        [System.IO.File]::ReadAllText($_.FullName) -match $contractPattern
    })
    if ($contractFiles.Count -ne 1) {
        throw "$($mutation.Id): expected one detector contract file, found $($contractFiles.Count)"
    }
    $detectorSource = [System.IO.File]::ReadAllText($contractFiles[0].FullName)
    $detectorPattern = "function\s+$([regex]::Escape($mutation.Test))\s*\("
    $detectorOccurrences = ([regex]::Matches($detectorSource, $detectorPattern)).Count
    if ($detectorOccurrences -ne 1) {
        throw "$($mutation.Id): expected one detector function, found $detectorOccurrences"
    }
}

if ($PreflightOnly) {
    Write-Output "mutation preflight PASS: $($mutations.Count) anchors and detectors"
    return
}

$sourceFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $repoRoot "implementation\src") -File -Recurse
    Get-ChildItem -LiteralPath (Join-Path $repoRoot "implementation\test") -File -Recurse
    Get-Item -LiteralPath (Join-Path $repoRoot "foundry.toml")
) | Sort-Object FullName
$repoPrefix = [System.IO.Path]::GetFullPath($repoRoot).TrimEnd('\') + '\'
$sourceRootMaterial = foreach ($file in $sourceFiles) {
    $fullName = [System.IO.Path]::GetFullPath($file.FullName)
    if (-not $fullName.StartsWith($repoPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "source file escaped repository root: $fullName"
    }
    $relative = $fullName.Substring($repoPrefix.Length).Replace('\', '/')
    "$(Get-Sha256 $file.FullName)  $relative`n"
}
$sourceRootBytes = [System.Text.Encoding]::UTF8.GetBytes(($sourceRootMaterial -join ""))
$sourceRootSha = Get-Sha256Bytes $sourceRootBytes

$previousNoColor = $env:NO_COLOR
$env:NO_COLOR = "1"
try {
    foreach ($mutation in $mutations) {
        Push-Location $repoRoot
        try {
            $baselineResult = Invoke-Forge @("test", "--match-contract", $mutation.Contract, "--match-test", $mutation.Test, "--fuzz-runs", "64", "-vv")
            $baselineOutput = @($baselineResult.Output)
            $baselineExitCode = $baselineResult.ExitCode
        } finally {
            Pop-Location
        }
        $baselineText = $baselineOutput -join "`n"
        $baselinePattern = "\[PASS\]\s+$([regex]::Escape($mutation.Test))\("
        if ($baselineExitCode -ne 0 -or $baselineText -notmatch $baselinePattern) {
            throw "$($mutation.Id): canonical detector did not execute and PASS"
        }
    }
} finally {
    if ($null -eq $previousNoColor) { Remove-Item Env:NO_COLOR -ErrorAction SilentlyContinue }
    else { $env:NO_COLOR = $previousNoColor }
}

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
    if ($mutation.ContainsKey("FirstOnly")) {
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
        $buildResult = Invoke-Forge @("build", "--force")
        $buildOutput = @($buildResult.Output)
        $buildExitCode = $buildResult.ExitCode
        if ($buildExitCode -ne 0) {
            throw "$($mutation.Id): mutant did not compile"
        }
        $testResult = Invoke-Forge @("test", "--match-contract", $mutation.Contract, "--match-test", $mutation.Test, "--fuzz-runs", "64", "-vv")
        $testOutput = @($testResult.Output)
        $testExitCode = $testResult.ExitCode
    } finally {
        Pop-Location
    }
    $testText = $testOutput -join "`n"
    $failurePattern = "\[FAIL[^\r\n]*\]\s+$([regex]::Escape($mutation.Test))\("
    if ($testExitCode -eq 0) {
        $result = "SURVIVED"
    } elseif ($testText -match $failurePattern) {
        $result = "KILLED"
    } else {
        throw "$($mutation.Id): detector infrastructure failed without an assertion failure`n$testText"
    }
    $results += [ordered]@{
        id = $mutation.Id
        fault = $mutation.Fault
        detector = "$($mutation.Contract).$($mutation.Test)"
        anchorOccurrences = $mutation.ExpectedOccurrences
        detectorDiscovered = 1
        detectorExecuted = 1
        mutantCompiled = $true
        result = $result
    }
}

$summary = [ordered]@{
    schema = "erc-trust-mutation-result-v1"
    candidateInput = [ordered]@{
        gitHead = (git -C $repoRoot rev-parse HEAD).Trim()
        sourceRootSha256 = $sourceRootSha
    }
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
    ([System.IO.Path]::GetFullPath($OutputPath)),
    $json,
    [System.Text.UTF8Encoding]::new($false))
$finalWorkspace = (Resolve-Path -LiteralPath $resolvedWorkspace).Path
if (-not $finalWorkspace.StartsWith($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Resolved mutation workspace escaped the system temporary directory after execution: $finalWorkspace"
}
Remove-Item -LiteralPath $finalWorkspace -Recurse -Force
$json
if ($summary.survived -ne 0) {
    exit 1
}
