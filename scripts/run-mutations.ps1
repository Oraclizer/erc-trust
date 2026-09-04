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
    $OutputPath = Join-Path $repoRoot "evidence/mutation-results.json"
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

# The canonical normalized campaign is a tracked JSON input shared by the runner and verifiers.
$campaignManifestPath = Join-Path $repoRoot "scripts/mutation-campaign-v1.json"
if (-not (Test-Path -LiteralPath $campaignManifestPath -PathType Leaf)) {
    throw "Mutation campaign manifest missing: $campaignManifestPath"
}
$campaignManifest = Get-Content -Raw -LiteralPath $campaignManifestPath | ConvertFrom-Json
if (($campaignManifest.schema -ne "erc-trust-mutation-campaign-v1") -or
    ($campaignManifest.algorithm -ne "sha256-canonical-json-sorted-keys-v1") -or
    [string]::IsNullOrWhiteSpace($campaignManifest.campaignDefinitionSha256)) {
    throw "Mutation campaign manifest identity drift"
}
$mutations = @($campaignManifest.definitions | ForEach-Object {
    $entry = [ordered]@{
        Id = $_.id
        Fault = $_.fault
        File = $_.file
        Old = $_.old
        New = $_.new
        ExpectedOccurrences = [int]$_.expectedOccurrences
        Contract = $_.detector.contract
        Test = $_.detector.test
    }
    if ([bool]$_.firstOnly) { $entry.FirstOnly = $true }
    $entry
})
$campaignDefinitionSha = $campaignManifest.campaignDefinitionSha256
$campaignDefinition = @($campaignManifest.definitions)

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

$testSourceFiles = Get-ChildItem -LiteralPath (Join-Path $repoRoot "implementation/test") -Filter "*.sol" -Recurse

foreach ($mutation in $mutations) {
    $target = Join-Path $repoRoot ($mutation.File -replace '\\', '/')
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
        throw "$($mutation.Id): target file missing: $($mutation.File)"
    }
    $content = [System.IO.File]::ReadAllText($target)
    $occurrences = Get-TextOccurrences $content $mutation.Old
    if ($occurrences -ne $mutation.ExpectedOccurrences) {
        throw "$($mutation.Id): expected $($mutation.ExpectedOccurrences) primary anchors, found $occurrences"
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

$sourceFileNames = [string[]]@(
    @(
        Get-ChildItem -LiteralPath (Join-Path $repoRoot "implementation/src") -File -Recurse
        Get-ChildItem -LiteralPath (Join-Path $repoRoot "implementation/test") -File -Recurse
        Get-Item -LiteralPath (Join-Path $repoRoot "foundry.toml")
    ) | ForEach-Object { $_.FullName }
)
[System.Array]::Sort($sourceFileNames, [System.StringComparer]::Ordinal)
$repoPrefix = [System.IO.Path]::GetFullPath($repoRoot).TrimEnd('\') + '\'
$sourceRootMaterial = foreach ($sourceFileName in $sourceFileNames) {
    $fullName = [System.IO.Path]::GetFullPath($sourceFileName)
    if (-not $fullName.StartsWith($repoPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "source file escaped repository root: $fullName"
    }
    $relative = $fullName.Substring($repoPrefix.Length).Replace('\', '/')
    "$(Get-Sha256 $fullName)  $relative`n"
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
    # The vector conformance test reads the generated vectors through the read-only filesystem permission.
    Copy-Item -LiteralPath (Join-Path $repoRoot "vectors") -Destination (Join-Path $caseRoot "vectors") -Recurse

    $target = Join-Path $caseRoot $mutation.File
    $content = [System.IO.File]::ReadAllText($target)
    if ($mutation.Contains("FirstOnly")) {
        $index = $content.IndexOf($mutation.Old)
        $content = $content.Remove($index, $mutation.Old.Length).Insert($index, $mutation.New)
    } else {
        $content = $content.Replace($mutation.Old, $mutation.New)
    }
    [System.IO.File]::WriteAllText($target, $content)

    Push-Location $caseRoot
    try {
        $buildResult = Invoke-Forge @("build", "--force")
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
    schema = "erc-trust-mutation-result-v2"
    campaignDefinitionAlgorithm = $campaignManifest.algorithm
    campaignDefinitionSha256 = $campaignDefinitionSha
    campaignDefinition = $campaignDefinition
    candidateInput = [ordered]@{
        gitHead = (git -C $repoRoot rev-parse HEAD).Trim()
        sourceRootAlgorithm = "sha256-raw-files-case-sensitive-path-order-v1"
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
