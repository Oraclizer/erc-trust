param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("canonical-final", "control-final", "canonical-event")]
    [string]$Lane,
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,
    [Parameter(Mandatory = $true)]
    [string]$CanonicalDefinitionDirectory,
    [Parameter(Mandatory = $true)]
    [string]$ControlDefinitionDirectory,
    [Parameter(Mandatory = $true)]
    [string]$ControlRoot,
    [switch]$ValidateOnly,
    [switch]$Execute,
    [int]$TimeoutSeconds = 7200,
    [string]$Distribution = "Ubuntu"
)

$ErrorActionPreference = "Stop"
if ($ValidateOnly -and $Execute) { throw "Choose ValidateOnly or Execute." }
if (-not $ValidateOnly -and -not $Execute) { throw "Heavy execution requires explicit Execute." }
if ($TimeoutSeconds -lt 300) { throw "TimeoutSeconds is too small for a heavy proof." }
if (-not [System.IO.Path]::IsPathRooted($OutputDirectory)) { throw "OutputDirectory must be absolute." }
$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $outputRoot) { throw "OutputDirectory already exists: $outputRoot" }

$bundleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $bundleRoot "..\..\..\.."))
$runtimeFreezePath = Join-Path $repositoryRoot "evidence\end-to-end-refinement\m4-runtime-freeze-v1.json"
$runtimeFreezeSha256 = "ba18d99f630bad67faee824ec83f1071f478a393639faa087be739d880164d67"
if ((Get-FileHash -LiteralPath $runtimeFreezePath -Algorithm SHA256).Hash.ToLower() -ne $runtimeFreezeSha256) { throw "runtime freeze drift" }

$claimContract = if ($Lane -eq "canonical-event") {
    [ordered]@{
        path = "formal/kevm/row-bundles/act-01/full-transaction-v1/full-transaction-event-order-spec.k"
        sha256 = "c41cdf5d1c07aababbdf5db451d41aee70fdebec815b98f3afaf0b3dfa06e621"
        module = "TRUST-ACT-01-FULL-TRANSACTION-EVENT-ORDER-SPEC"
    }
} else {
    [ordered]@{
        path = "formal/kevm/row-bundles/act-01/full-transaction-v1/full-transaction-finalization-spec.k"
        sha256 = "ae567db2edcaff283da78fb7fe8ed5843d6c89c56809527b2270496fe1f6ef9f"
        module = "TRUST-ACT-01-FULL-TRANSACTION-FINALIZATION-SPEC"
    }
}
$claimSource = Join-Path $repositoryRoot $claimContract.path
if ((Get-FileHash -LiteralPath $claimSource -Algorithm SHA256).Hash.ToLower() -ne $claimContract.sha256) { throw "claim drift" }

$isControl = $Lane -eq "control-final"
$definitionRoot = [System.IO.Path]::GetFullPath($(if ($isControl) { $ControlDefinitionDirectory } else { $CanonicalDefinitionDirectory }))
$definitionRef = if ($isControl) { "external-definition/act-01-state-restoration-control" } else { "external-definition/canonical-runtime-verification" }
$definitionKoreSha256 = if ($isControl) { "13dd630fbe5142b2da26a4597ffb13648e627eafc2074e4da8ec24a9555c3c15" } else { "bac21e3e90990c4c060bf77ecfe161a70d18900c631dcea5a37343765e6b3e33" }
$compiledJsonSha256 = if ($isControl) { "4990f62629f98d07676eedf9d4aefcb2ce4ddffaaafac8675147fb470cdde67c" } else { "5ba6257f64024f7eff4ec99c569db9f9477fd5d2a625f44ed04e091fdf795a50" }
$expectedExitCode = if ($isControl) { 1 } else { 0 }
$expectedMarker = if ($isControl) { "PROOF FAILED:" } else { "PROOF PASSED:" }
if ((Get-FileHash -LiteralPath (Join-Path $definitionRoot "definition.kore") -Algorithm SHA256).Hash.ToLower() -ne $definitionKoreSha256) { throw "definition.kore drift" }
if ((Get-FileHash -LiteralPath (Join-Path $definitionRoot "compiled.json") -Algorithm SHA256).Hash.ToLower() -ne $compiledJsonSha256) { throw "compiled.json drift" }
if ((Get-Content -LiteralPath (Join-Path $definitionRoot "mainModule.txt") -Raw).Trim() -ne "TRUST-RUNTIME-VERIFICATION") { throw "main module drift" }
if ((Get-Content -LiteralPath (Join-Path $definitionRoot "backend.txt") -Raw).Trim() -ne "haskell") { throw "backend drift" }

if ($isControl) {
    $controlRootPath = [System.IO.Path]::GetFullPath($ControlRoot)
    if ((Get-FileHash -LiteralPath (Join-Path $controlRootPath "control-report.json") -Algorithm SHA256).Hash.ToLower() -ne "8d59bee02e096206006ed2097a57b03b401e24f54c473e771f7751c56cd080b6") { throw "control report drift" }
    if ((Get-FileHash -LiteralPath (Join-Path $controlRootPath "definition-build-result.json") -Algorithm SHA256).Hash.ToLower() -ne "f76033c9ec0077293a7f474b76b25dcbbb45bbdbad71ffef9ddfa1e9ee272721") { throw "control build result drift" }
}

$kevmPath = "/nix/store/cj49dhi36y3vzjfs8bjz5g9m7rk20p53-kevm-pyk-env/bin/kevm"
$kBin = "/nix/store/y63xkr8pk2bqd5lh4889rlwldw26v9f4-k-7.1.337-4a46d1231473b599c699160132fd6e76a5c46406/bin"
$kprovePath = "$kBin/kprove"
$koreRpcPath = "/nix/store/wij5nr1s0q3ksvyng4lcybhy467bn9gh-kore-rpc/bin/kore-rpc"
$z3Bin = "/nix/store/ih51sgk8g57fnkbd5r82ddi8k5vln8cl-z3-4.13.4/bin"
$z3Path = "$z3Bin/z3"
$pinnedPath = "/nix/store/cj49dhi36y3vzjfs8bjz5g9m7rk20p53-kevm-pyk-env/bin:${kBin}:/nix/store/wij5nr1s0q3ksvyng4lcybhy467bn9gh-kore-rpc/bin:${z3Bin}:/usr/bin:/bin"
$expectedTools = @{
    $kevmPath = "f484a67969a0a0869645fef86778a04b638bde9b524ad0ee0a51043b08839754"
    $kprovePath = "21a7dea3c7c648691eca2629abddebb75ed8ed20466a12536f6d3dbb2816ae67"
    $koreRpcPath = "9bac312641781abfad1aee58925a5feae7d4102ad4ab5ef57e28357a5422d456"
    $z3Path = "2a5132e5f73510ab0ebb61fa8996bfa303f5473a85add71eedbd9c6819ff43ef"
}
function Get-WslSha256([string]$Path) {
    $line = & wsl.exe -d $Distribution -e sha256sum $Path
    if ($LASTEXITCODE -ne 0 -or -not $line) { throw "sha256sum failed: $Path" }
    return ($line -split "\s+")[0].ToLower()
}
foreach ($path in $expectedTools.Keys) {
    if ((Get-WslSha256 $path) -ne $expectedTools[$path]) { throw "tool drift: $path" }
}

$commandManifest = [ordered]@{
    schemaVersion = 1
    obligationId = "ACT-01"
    lane = $Lane
    claimSha256 = $claimContract.sha256
    specModule = $claimContract.module
    definitionRef = $definitionRef
    definitionKoreSha256 = $definitionKoreSha256
    compiledJsonSha256 = $compiledJsonSha256
    runtimeFreezeSha256 = $runtimeFreezeSha256
    timeoutSeconds = $TimeoutSeconds
    workers = 1
    booster = $false
    expectedExitCode = $expectedExitCode
    expectedMarker = $expectedMarker
}
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$sha = [System.Security.Cryptography.SHA256]::Create()
try {
    $commandManifestSha256 = ([System.BitConverter]::ToString($sha.ComputeHash($utf8NoBom.GetBytes(($commandManifest | ConvertTo-Json -Depth 6 -Compress))))).Replace("-", "").ToLower()
} finally { $sha.Dispose() }

if ($ValidateOnly) {
    [ordered]@{
        schemaVersion = 1
        status = "PASS_HEAVY_VALIDATION_NO_BACKEND"
        lane = $Lane
        claimSha256 = $claimContract.sha256
        definitionRef = $definitionRef
        definitionKoreSha256 = $definitionKoreSha256
        compiledJsonSha256 = $compiledJsonSha256
        commandManifestSha256 = $commandManifestSha256
        expectedExitCode = $expectedExitCode
        creditEligible = $false
    } | ConvertTo-Json -Depth 6
    return
}

New-Item -ItemType Directory -Path $outputRoot | Out-Null
$saveRoot = Join-Path $outputRoot "save"
$tempRoot = Join-Path $outputRoot "temp"
New-Item -ItemType Directory -Path $saveRoot | Out-Null
New-Item -ItemType Directory -Path $tempRoot | Out-Null
$executedClaimPath = Join-Path $outputRoot "claim.k"
$logPath = Join-Path $outputRoot "prove.log"
$timePath = Join-Path $outputRoot "time.txt"
$exitCodePath = Join-Path $outputRoot "exit-code.txt"
$resultPath = Join-Path $outputRoot "result.json"
$claimLines = [System.IO.File]::ReadAllLines($claimSource)
if (-not $claimLines[0].StartsWith("requires ")) { throw "claim header drift" }
[System.IO.File]::WriteAllText($executedClaimPath, (($claimLines | Select-Object -Skip 1) -join "`n") + "`n", $utf8NoBom)
function Convert-ToWslPath([string]$WindowsPath) {
    $converted = & wsl.exe -d $Distribution -e wslpath -a $WindowsPath
    if ($LASTEXITCODE -ne 0) { throw "wslpath failed" }
    return $converted.Trim()
}
$claimWsl = Convert-ToWslPath $executedClaimPath
$definitionWsl = Convert-ToWslPath $definitionRoot
$saveWsl = Convert-ToWslPath $saveRoot
$tempWsl = Convert-ToWslPath $tempRoot
$logWsl = Convert-ToWslPath $logPath
$timeWsl = Convert-ToWslPath $timePath
$command = "set -o pipefail; export PATH='$pinnedPath'; export K_OPTS='-Xmx5g'; /usr/bin/time -f '%U %S' -o '$timeWsl' /usr/bin/timeout --foreground --signal=TERM --kill-after=30s ${TimeoutSeconds}s '$kevmPath' prove '$claimWsl' --definition '$definitionWsl' --spec-module '$($claimContract.module)' --save-directory '$saveWsl' --temp-directory '$tempWsl' --workers 1 --force-sequential --no-use-booster --kore-rpc-command '$koreRpcPath' --failure-information 2>&1 | /usr/bin/tee '$logWsl' >/dev/null"
$startedAt = (Get-Date).ToUniversalTime()
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
& wsl.exe -d $Distribution -e bash -lc $command
$exitCode = $LASTEXITCODE
$stopwatch.Stop()
$endedAt = (Get-Date).ToUniversalTime()
[System.IO.File]::WriteAllText($exitCodePath, "$exitCode`n", $utf8NoBom)
$logText = if (Test-Path -LiteralPath $logPath) { [System.IO.File]::ReadAllText($logPath) } else { "" }
$timedOut = $exitCode -eq 124 -or $exitCode -eq 137
$markerPresent = $logText.Contains($expectedMarker)
$runtimeFailure = $logText -match "Traceback|Internal error|RuntimeError|parse error"
$proofArtifactsPresent = (Get-ChildItem -LiteralPath $saveRoot -Recurse -File).Count -gt 0
$classification = if ($timedOut) { "INCOMPLETE_TIMEOUT" } elseif ($exitCode -ne $expectedExitCode) { "UNEXPECTED_EXIT" } elseif (-not $markerPresent -or $runtimeFailure -or -not $proofArtifactsPresent) { "INVALID_RESULT_SHAPE" } elseif ($isControl) { "PASS_EXPECTED_SEMANTIC_CONTROL_FAILURE" } else { "PASS_CANONICAL_POSITIVE" }
$cpuMs = $null
if (Test-Path -LiteralPath $timePath) {
    $timeLines = [System.IO.File]::ReadAllLines($timePath)
    $numericLine = $timeLines | Where-Object { $_ -match '^\s*[0-9]+(?:\.[0-9]+)?\s+[0-9]+(?:\.[0-9]+)?\s*$' } | Select-Object -Last 1
    if ($numericLine) {
        $parts = ($numericLine.Trim() -split "\s+")
        $cpuMs = [int64](([double]$parts[0] + [double]$parts[1]) * 1000)
    }
}
$result = [ordered]@{
    schemaVersion = 1
    kind = "ACT01_FULL_TRANSACTION_HEAVY_RESULT_V1"
    obligationId = "ACT-01"
    lane = $Lane
    status = $classification
    outputRootRef = "external-scratch/" + (Split-Path -Leaf $outputRoot)
    claimPath = $claimContract.path.Replace("\", "/")
    claimSourceSha256 = $claimContract.sha256
    executedClaimSha256 = (Get-FileHash -LiteralPath $executedClaimPath -Algorithm SHA256).Hash.ToLower()
    unchangedClaimAcrossDefinitions = $true
    specModule = $claimContract.module
    definitionRef = $definitionRef
    definitionKoreSha256 = $definitionKoreSha256
    compiledJsonSha256 = $compiledJsonSha256
    runtimeFreezeSha256 = $runtimeFreezeSha256
    commandManifestSha256 = $commandManifestSha256
    timeoutSeconds = $TimeoutSeconds
    startedAtUtc = $startedAt.ToString("o")
    endedAtUtc = $endedAt.ToString("o")
    wallMs = $stopwatch.ElapsedMilliseconds
    cpuMs = $cpuMs
    expectedExitCode = $expectedExitCode
    actualExitCode = $exitCode
    timedOut = $timedOut
    expectedMarker = $expectedMarker
    expectedMarkerPresent = $markerPresent
    runtimeFailureMarkerPresent = [bool]$runtimeFailure
    proofArtifactsPresent = $proofArtifactsPresent
    logSha256 = if (Test-Path -LiteralPath $logPath) { (Get-FileHash -LiteralPath $logPath -Algorithm SHA256).Hash.ToLower() } else { $null }
    proofExecuted = $true
    creditEligible = $false
    centralCredit = $false
}
[System.IO.File]::WriteAllText($resultPath, (($result | ConvertTo-Json -Depth 8) + "`n"), $utf8NoBom)
($result | ConvertTo-Json -Depth 8) + "`n"
if ($classification -notlike "PASS_*") { throw "heavy lane failed exact contract: $classification" }
