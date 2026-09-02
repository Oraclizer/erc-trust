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

# Each fault removes or weakens one load-bearing consumer of the kernel version 2 native endpoint.
# The detector is the exact Foundry test that must fail once the consumer is gone.
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
        Test = "testERC7943ExactUseRoutesAndRawClosure"
    },
    @{
        Id = "MUT-03-RECEIPT-LAST"
        Fault = "Emit a base event after the canonical TRUST receipt"
        File = "implementation\src\TrustToken.sol"
        Old = "emit RegulatoryActionApplied(request.actionId, uint8(request.action), request.caseId, receiptHash);"
        New = "emit RegulatoryActionApplied(request.actionId, uint8(request.action), request.caseId, receiptHash);`n        emit Frozen(request.subject, _frozen[request.subject]);"
        ExpectedOccurrences = 1
        Contract = "TrustActionsUnitTest"
        Test = "testCanonicalEventOrderAndRevertedTransactionsLeaveNothing"
    },
    @{
        Id = "MUT-04-FAIL-CLOSED"
        Fault = "Allow OperationalFailure assessment to continue"
        File = "implementation\src\TrustToken.sol"
        Old = "if (outcome == TrustKernelTypes.AssessmentOutcome.OPERATIONAL_FAILURE) {"
        New = "if (false) {"
        ExpectedOccurrences = 1
        Contract = "TrustActionsUnitTest"
        Test = "testAssessmentOutcomesAndReasonClasses"
    },
    @{
        Id = "MUT-05-FIXED-ACTION"
        Fault = "Remove destination from action-id binding"
        File = "implementation\src\TrustToken.sol"
        Old = "calldatacopy(add(ptr, 0x60), request, 0x280)`n            if clearId { mstore(add(ptr, 0x80), 0) }"
        New = "calldatacopy(add(ptr, 0x60), request, 0x280)`n            if clearId {`n                mstore(add(ptr, 0x80), 0)`n                mstore(add(ptr, 0x100), 0)`n            }"
        ExpectedOccurrences = 1
        Contract = "TrustKernelVectorsTest"
        Test = "testFieldBindingNegativeVectors"
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
        Test = "testFreezeAmendmentChainReopensAfterPop"
    },
    @{
        Id = "MUT-09-CASE-TERMINALITY"
        Fault = "Leave a disposition case open instead of terminal"
        File = "implementation\src\TrustToken.sol"
        Old = "if (!consumedCustody) caseState.family = TrustKernelTypes.CaseFamily.DISPOSITION;`n            caseState.phase = TrustKernelTypes.CasePhase.TERMINAL;"
        New = "if (!consumedCustody) caseState.family = TrustKernelTypes.CaseFamily.DISPOSITION;`n            caseState.phase = TrustKernelTypes.CasePhase.OPEN;"
        ExpectedOccurrences = 1
        Contract = "TrustActionsUnitTest"
        Test = "testDispositionOnOpenOverlayCaseIsRejectedAndTerminalCasesRejectReversals"
    },
    @{
        Id = "MUT-10-CUSTODY-CLOSURE"
        Fault = "Skip matched custody closure before disposition"
        File = "implementation\src\TrustToken.sol"
        Old = "if (!custody.active) return false;"
        New = "return false;"
        ExpectedOccurrences = 1
        Contract = "TrustActionsUnitTest"
        Test = "testCustodyLifecycleAndDispositions"
    },
    @{
        Id = "MUT-11-REVERSAL-POLICY"
        Fault = "Skip current-policy assessment before direct reversal"
        File = "implementation\src\TrustToken.sol"
        Old = "bytes32 evidence = _assessReversalOrRevert(request, digest);"
        New = "bytes32 evidence = digest;"
        ExpectedOccurrences = 2
        FirstOnly = $true
        Contract = "TrustActionsUnitTest"
        Test = "testReversalAssessmentFailsClosedAfterPolicyRebind"
    },
    @{
        Id = "MUT-12-ERC3643-FREEZE-DIRECTION"
        Fault = "Permit equal or decreasing targets through the ERC-3643 profile"
        File = "implementation\src\profiles\ERC3643TrustAdapter.sol"
        Old = "request.amount <= _owned[request.subject].frozenTarget"
        New = "false"
        ExpectedOccurrences = 1
        Contract = "ERC3643ProfileUnitTest"
        Test = "testAllSixActionsAndReversals"
    },
    @{
        Id = "MUT-13-TERMINAL-REVERSAL-GUARD"
        Fault = "Remove the terminal-case guard from reversal validation"
        File = "implementation\src\TrustToken.sol"
        Old = "if (_cases[original.caseId].phase == TrustKernelTypes.CasePhase.TERMINAL) {`n            revert TrustTerminal(original.caseId);`n        }"
        New = ""
        ExpectedOccurrences = 1
        Contract = "TrustActionsUnitTest"
        Test = "testDispositionOnOpenOverlayCaseIsRejectedAndTerminalCasesRejectReversals"
    },
    @{
        Id = "MUT-14-DEPENDENCY-ROOT-COMPARISON"
        Fault = "Compare only the dependency epoch and ignore the root"
        File = "implementation\src\TrustToken.sol"
        Old = "if (request.dependencyRoot != _dependencyRoot || request.dependencyEpoch != _dependencyEpoch) {`n            revert TrustInvalidCommand(request.actionId, REASON_DEPENDENCY_BINDING);"
        New = "if (request.dependencyEpoch != _dependencyEpoch) {`n            revert TrustInvalidCommand(request.actionId, REASON_DEPENDENCY_BINDING);"
        ExpectedOccurrences = 1
        Contract = "TrustActionsUnitTest"
        Test = "testRootAndEpochAreCheckedIndependently"
    },
    @{
        Id = "MUT-15-DEPENDENCY-EPOCH-INCREMENT"
        Fault = "Do not advance the global dependency epoch on rebind"
        File = "implementation\src\TrustToken.sol"
        Old = "_dependencyEpoch += 1;"
        New = "_dependencyEpoch += 0;"
        ExpectedOccurrences = 1
        Contract = "TrustActionsUnitTest"
        Test = "testEveryDependencyRebindMakesEarlierCommandsStale"
    },
    @{
        Id = "MUT-16-ROOT-TAG"
        Fault = "Compute the dependency root without its domain-separation tag"
        File = "implementation\src\TrustNativeDecision.sol"
        Old = "TrustKernelTypes.DOMAIN, TrustKernelTypes.DEPENDENCY_ROOT_TAG, policy, identity, settlement, entitlement"
        New = "TrustKernelTypes.DOMAIN, bytes32(0), policy, identity, settlement, entitlement"
        ExpectedOccurrences = 1
        Contract = "TrustActionsUnitTest"
        Test = "testDependencyRootFormulaAndInitialEvents"
    },
    @{
        Id = "MUT-17-ROOT-ORDER"
        Fault = "Swap the identity and settlement bindings in the dependency root"
        File = "implementation\src\TrustNativeDecision.sol"
        Old = "TrustKernelTypes.DOMAIN, TrustKernelTypes.DEPENDENCY_ROOT_TAG, policy, identity, settlement, entitlement"
        New = "TrustKernelTypes.DOMAIN, TrustKernelTypes.DEPENDENCY_ROOT_TAG, policy, settlement, identity, entitlement"
        ExpectedOccurrences = 1
        Contract = "TrustActionsUnitTest"
        Test = "testDependencyRootFormulaAndInitialEvents"
    },
    @{
        Id = "MUT-18-CASE-CONFLICT"
        Fault = "Allow an overlay head owned by another case to be stacked"
        File = "implementation\src\TrustToken.sol"
        Old = "} else if (caseState.headActionId != head.actionId) {"
        New = "} else if (false) {"
        ExpectedOccurrences = 1
        Contract = "TrustActionsUnitTest"
        Test = "testOverlayCaseConflictsAndFamilies"
    },
    @{
        Id = "MUT-19-OVERLAY-DISPOSITION"
        Fault = "Allow a disposition against an open overlay case"
        File = "implementation\src\TrustToken.sol"
        Old = "if (caseState.family != TrustKernelTypes.CaseFamily.CUSTODY) {`n                        revert TrustInvalidCommand(request.actionId, REASON_CASE_CONFLICT);"
        New = "if (false) {`n                        revert TrustInvalidCommand(request.actionId, REASON_CASE_CONFLICT);"
        ExpectedOccurrences = 1
        Contract = "TrustActionsUnitTest"
        Test = "testDispositionOnOpenOverlayCaseIsRejectedAndTerminalCasesRejectReversals"
    },
    @{
        Id = "MUT-20-RECEIPT-KIND-TAG"
        Fault = "Tag reversal receipts as action receipts"
        File = "implementation\src\TrustToken.sol"
        Old = "receiptKind: TrustKernelTypes.ReceiptKind.REVERSAL,"
        New = "receiptKind: TrustKernelTypes.ReceiptKind.ACTION,"
        ExpectedOccurrences = 1
        Contract = "TrustActionsUnitTest"
        Test = "testReceiptBindsCanonicalCommandHashEvidenceAndFinalEvent"
    },
    @{
        Id = "MUT-21-REVERSAL-CLOSES-CHAIN"
        Fault = "Close the case after every unfreeze even when an amendment parent remains"
        File = "implementation\src\TrustToken.sol"
        Old = "if (parent != bytes32(0)) {`n                caseState.headActionId = parent;`n            } else {`n                _closeCase(caseState);`n            }"
        New = "_closeCase(caseState);"
        ExpectedOccurrences = 1
        Contract = "TrustActionsUnitTest"
        Test = "testFreezeAmendmentChainReopensAfterPop"
    },
    @{
        Id = "MUT-22-RECEIPT-PREIMAGE"
        Fault = "Drop the last receipt field from the hash preimage"
        File = "implementation\src\TrustToken.sol"
        Old = "mcopy(add(ptr, 0x20), record, 0x200)"
        New = "mcopy(add(ptr, 0x20), record, 0x1e0)"
        ExpectedOccurrences = 1
        Contract = "TrustActionsUnitTest"
        Test = "testSixActionsAndThreeReversalsWithReceipts"
    },
    @{
        Id = "MUT-23-CALLDATA-LENGTH"
        Fault = "Accept action calldata of any length on both action entrypoints"
        File = "implementation\src\TrustToken.sol"
        Old = "_requireCalldataLength(ACTION_CALLDATA_LENGTH);"
        New = ""
        ExpectedOccurrences = 2
        Contract = "TrustActionsUnitTest"
        Test = "testNonCanonicalCalldataIsRejected"
    },
    @{
        Id = "MUT-24-IDENTITY-ASSESSMENT"
        Fault = "Skip the identity dependency for transfer actions"
        File = "implementation\src\TrustToken.sol"
        Old = "if (request.destination != address(0)) {"
        New = "if (false) {"
        ExpectedOccurrences = 1
        Contract = "TrustActionsUnitTest"
        Test = "testAssessmentOutcomesAndReasonClasses"
    },
    @{
        Id = "MUT-25-BINDING-ECHO"
        Fault = "Accept a dependency response whose binding echo does not match the bound binding"
        File = "implementation\src\TrustDependencyBinding.sol"
        Old = "if (commandEcho != commandHash || bindingEcho != binding.bindingHash) {"
        New = "if (commandEcho != commandHash) {"
        ExpectedOccurrences = 1
        Contract = "TrustActionsUnitTest"
        Test = "testAssessmentOutcomesAndReasonClasses"
    },
    @{
        Id = "MUT-26-REVERSAL-CALLDATA-LENGTH"
        Fault = "Accept reversal calldata of any length on both reversal entrypoints"
        File = "implementation\src\TrustToken.sol"
        Old = "_requireCalldataLength(REVERSAL_CALLDATA_LENGTH);"
        New = ""
        ExpectedOccurrences = 2
        Contract = "TrustActionsUnitTest"
        Test = "testNonCanonicalCalldataIsRejected"
    },
    # ERC-3643 Verified Full profile: each fault removes or weakens one load-bearing consumer of the adapter
    # (or of the governor) on kernel version 2. The detectors run against the clean-room fixture; the same
    # suite also runs against the independent second fixture in continuous integration.
    @{
        Id = "MUT-27-ERC3643-OWNED-UPSTREAM-STATE"
        Fault = "Act on upstream frozen or restricted state the adapter never declared or applied"
        File = "implementation\src\profiles\ERC3643TrustAdapter.sol"
        Old = "            _upstreamFrozen(commandId, account) != owned.appliedFrozen`n                || _upstreamRestricted(commandId, account) != owned.restricted"
        New = "false"
        ExpectedOccurrences = 1
        Contract = "ERC3643ProfileUnitTest"
        Test = "testUndeclaredUpstreamStateFailsClosed"
    },
    @{
        Id = "MUT-28-ERC3643-IMPORT-VERIFICATION"
        Fault = "Import a manifest entry without verifying it against the live upstream state"
        File = "implementation\src\profiles\ERC3643TrustAdapter.sol"
        Old = "            _upstreamFrozen(bytes32(0), entry.account) != entry.frozenAmount`n                || _upstreamRestricted(bytes32(0), entry.account) != entry.restricted"
        New = "false"
        ExpectedOccurrences = 1
        Contract = "ERC3643ProfileUnitTest"
        Test = "testImportManifestMustMatchUpstreamExactly"
    },
    @{
        Id = "MUT-29-ERC3643-TOPOLOGY-GATE"
        Fault = "Execute without checking that the sealed topology still holds"
        File = "implementation\src\profiles\ERC3643TrustAdapter.sol"
        Old = "if (!_sealed || !profileGovernor.isFull(address(this))) {"
        New = "if (!_sealed) {"
        ExpectedOccurrences = 1
        Contract = "ERC3643ProfileUnitTest"
        Test = "testTopologyDriftFailsClosedAndClearsFull"
    },
    @{
        Id = "MUT-30-ERC3643-DEPENDENCY-CODE"
        Fault = "Execute against a Compliance whose runtime code changed since the seal"
        File = "implementation\src\profiles\ERC3643TrustAdapter.sol"
        Old = "if (!_bindingLive(TrustKernelTypes.BindingKind.POLICY)) {"
        New = "if (false) {"
        ExpectedOccurrences = 1
        Contract = "ERC3643ProfileUnitTest"
        Test = "testDependencyCodeDriftFailsClosed"
    },
    @{
        Id = "MUT-31-ERC3643-TRANSFER-POSTSTATE"
        Fault = "Trust the forced transfer return value instead of verifying both balances"
        File = "implementation\src\profiles\ERC3643TrustAdapter.sol"
        Old = "        if (`n            beforeFrom < amount || _upstreamBalance(commandId, from) != beforeFrom - amount`n                || _upstreamBalance(commandId, to) != beforeTo + amount`n        ) {"
        New = "        if (beforeFrom < amount) {"
        ExpectedOccurrences = 1
        Contract = "ERC3643ProfileUnitTest"
        Test = "testUpstreamFailureModesAreTyped"
    },
    @{
        Id = "MUT-32-ERC3643-FROZEN-POSTSTATE"
        Fault = "Skip the frozen-amount post-state check after a freeze or unfreeze call"
        File = "implementation\src\profiles\ERC3643TrustAdapter.sol"
        Old = "if (_upstreamFrozen(commandId, account) != expected) {"
        New = "if (false) {"
        ExpectedOccurrences = 1
        Contract = "ERC3643ProfileUnitTest"
        Test = "testUpstreamFailureModesAreTyped"
    },
    @{
        Id = "MUT-33-ERC3643-TERMINAL-REVERSAL-GUARD"
        Fault = "Remove the terminal-case guard from reversal validation"
        File = "implementation\src\profiles\ERC3643TrustAdapter.sol"
        Old = "        if (_cases[original.caseId].phase == TrustKernelTypes.CasePhase.TERMINAL) {`n            revert TrustTerminal(original.caseId);`n        }"
        New = ""
        ExpectedOccurrences = 1
        Contract = "ERC3643ProfileUnitTest"
        Test = "testDispositionOnOpenOverlayCaseIsRejectedAndTerminalCasesRejectReversals"
    },
    @{
        Id = "MUT-34-ERC3643-DEPENDENCY-ROOT-COMPARISON"
        Fault = "Compare only the dependency epoch and ignore the root"
        File = "implementation\src\profiles\ERC3643TrustAdapter.sol"
        Old = "if (request.dependencyRoot != _dependencyRoot || request.dependencyEpoch != _dependencyEpoch) {`n            revert TrustInvalidCommand(request.actionId, REASON_DEPENDENCY_BINDING);"
        New = "if (request.dependencyEpoch != _dependencyEpoch) {`n            revert TrustInvalidCommand(request.actionId, REASON_DEPENDENCY_BINDING);"
        ExpectedOccurrences = 1
        Contract = "ERC3643ProfileUnitTest"
        Test = "testRootAndEpochAreCheckedIndependently"
    },
    @{
        Id = "MUT-35-ERC3643-ROOT-TAG"
        Fault = "Compute the profile dependency root without its domain-separation tag"
        File = "implementation\src\profiles\ERC3643TrustAdapter.sol"
        Old = "                TrustKernelTypes.DEPENDENCY_ROOT_TAG,"
        New = "                bytes32(0),"
        ExpectedOccurrences = 1
        Contract = "ERC3643ProfileUnitTest"
        Test = "testDescriptorDependencyStateAndInterfaceIdentifiers"
    },
    @{
        Id = "MUT-36-ERC3643-CUSTODIAN-CONFINEMENT"
        Fault = "Accept any nonzero custodian instead of confining custody to the adapter"
        File = "implementation\src\profiles\ERC3643TrustAdapter.sol"
        Old = "request.subject != request.source || request.custodian != address(this)"
        New = "request.subject != request.source || request.custodian == address(0)"
        ExpectedOccurrences = 1
        Contract = "ERC3643ProfileUnitTest"
        Test = "testCustodyLifecycleAndConfinement"
    },
    @{
        Id = "MUT-37-ERC3643-IDENTITY-ASSESSMENT"
        Fault = "Skip the Identity Registry for the destination of a transfer action"
        File = "implementation\src\profiles\ERC3643TrustAdapter.sol"
        Old = "            _assessIdentity(request.actionId, request.destination);"
        New = ""
        ExpectedOccurrences = 1
        Contract = "ERC3643ProfileUnitTest"
        Test = "testRejectedAndOperationalFailureFailClosedWithStutter"
    },
    @{
        Id = "MUT-38-ERC3643-COMPLIANCE-ASSESSMENT"
        Fault = "Skip the Compliance policy for a transfer action"
        File = "implementation\src\profiles\ERC3643TrustAdapter.sol"
        Old = "            _assessCompliance(request.actionId, request.source, request.destination, request.amount);"
        New = ""
        ExpectedOccurrences = 1
        Contract = "ERC3643ProfileUnitTest"
        Test = "testRejectedAndOperationalFailureFailClosedWithStutter"
    },
    @{
        Id = "MUT-39-ERC3643-RECEIPT-KIND-TAG"
        Fault = "Tag adapter reversal receipts as action receipts"
        File = "implementation\src\profiles\ERC3643TrustAdapter.sol"
        Old = "receiptKind: TrustKernelTypes.ReceiptKind.REVERSAL,"
        New = "receiptKind: TrustKernelTypes.ReceiptKind.ACTION,"
        ExpectedOccurrences = 1
        Contract = "ERC3643ProfileUnitTest"
        Test = "testReceiptBindsEvidenceAuthorityRootAndFinalEvent"
    },
    @{
        Id = "MUT-40-ERC3643-CASE-CONFLICT"
        Fault = "Allow an overlay head owned by another case to be stacked"
        File = "implementation\src\profiles\ERC3643TrustAdapter.sol"
        Old = "} else if (caseState.headActionId != head.actionId) {"
        New = "} else if (false) {"
        ExpectedOccurrences = 1
        Contract = "ERC3643ProfileUnitTest"
        Test = "testOverlayCaseConflictsAndFamilies"
    },
    @{
        Id = "MUT-41-ERC3643-CALLDATA-LENGTH"
        Fault = "Accept action calldata of any length"
        File = "implementation\src\profiles\ERC3643TrustAdapter.sol"
        Old = "_requireCalldataLength(ACTION_CALLDATA_LENGTH);"
        New = ""
        ExpectedOccurrences = 1
        Contract = "ERC3643ProfileUnitTest"
        Test = "testNonCanonicalCalldataIsRejected"
    },
    @{
        Id = "MUT-42-ERC3643-REVERSAL-CALLDATA-LENGTH"
        Fault = "Accept reversal calldata of any length"
        File = "implementation\src\profiles\ERC3643TrustAdapter.sol"
        Old = "_requireCalldataLength(REVERSAL_CALLDATA_LENGTH);"
        New = ""
        ExpectedOccurrences = 1
        Contract = "ERC3643ProfileUnitTest"
        Test = "testNonCanonicalCalldataIsRejected"
    },
    @{
        Id = "MUT-43-ERC3643-NONCE-CONSUMPTION"
        Fault = "Do not consume the nonce of an action or a reversal"
        File = "implementation\src\profiles\ERC3643TrustAdapter.sol"
        Old = "_usedNonces[_nonceKey(request.authorityRef, request.authorityEpoch, request.nonce)] = true;"
        New = "_usedNonces[_nonceKey(request.authorityRef, request.authorityEpoch, request.nonce)] = false;"
        ExpectedOccurrences = 2
        Contract = "ERC3643ProfileUnitTest"
        Test = "testReplayNonceAndAuthority"
    },
    @{
        Id = "MUT-44-ERC3643-MANIFEST-BINDING"
        Fault = "Seal a binding that does not commit to the import manifest"
        File = "implementation\src\profiles\ProfileGovernor.sol"
        Old = "                compliance,`n                manifestHash"
        New = "                compliance,`n                bytes32(0)"
        ExpectedOccurrences = 1
        Contract = "ERC3643ProfileUnitTest"
        Test = "testExactImportManifestOpensReversibleCases"
    },
    @{
        Id = "MUT-45-ERC3643-IMPORTED-CASE"
        Fault = "Import a declared frozen amount without opening its case and live head"
        File = "implementation\src\profiles\ERC3643TrustAdapter.sol"
        Old = "if (entry.frozenAmount != 0) {"
        New = "if (false) {"
        ExpectedOccurrences = 1
        Contract = "ERC3643ProfileUnitTest"
        Test = "testExactImportManifestOpensReversibleCases"
    },
    @{
        Id = "MUT-46-ERC3643-CUSTODY-CLOSURE"
        Fault = "Skip matched custody closure before a custody disposition"
        File = "implementation\src\profiles\ERC3643TrustAdapter.sol"
        Old = "if (!custody.active) return false;"
        New = "return false;"
        ExpectedOccurrences = 1
        Contract = "ERC3643ProfileUnitTest"
        Test = "testDispositionOnOpenOverlayCaseIsRejectedAndTerminalCasesRejectReversals"
    },
    @{
        Id = "MUT-47-ERC3643-REVERSAL-CLOSES-CHAIN"
        Fault = "Close the case after every unfreeze even when an amendment parent remains"
        File = "implementation\src\profiles\ERC3643TrustAdapter.sol"
        Old = "if (parent != bytes32(0)) {"
        New = "if (false) {"
        ExpectedOccurrences = 1
        Contract = "ERC3643ProfileUnitTest"
        Test = "testAllSixActionsAndReversals"
    },
    @{
        Id = "MUT-48-ERC3643-REVERSAL-OWNED-STATE"
        Fault = "Reverse an overlay without checking that the subject's upstream state is owned"
        File = "implementation\src\profiles\ERC3643TrustAdapter.sol"
        Old = "            _requireOwnedUpstreamState(request.reversalId, original.subject);"
        New = ""
        ExpectedOccurrences = 1
        Contract = "ERC3643ProfileUnitTest"
        Test = "testDriftedUpstreamStateFailsClosedOnEveryTouchedAccount"
    },
    @{
        Id = "MUT-49-ERC3643-CUSTODIAN-OWNED-STATE"
        Fault = "Seize without checking that the custodian's upstream state is owned"
        File = "implementation\src\profiles\ERC3643TrustAdapter.sol"
        Old = "            _requireOwnedUpstreamState(request.actionId, request.custodian);"
        New = ""
        ExpectedOccurrences = 1
        Contract = "ERC3643ProfileUnitTest"
        Test = "testDriftedUpstreamStateFailsClosedOnEveryTouchedAccount"
    },
    @{
        Id = "MUT-50-ERC3643-RESYNC-OWNED-STATE"
        Fault = "Resynchronise an account without checking that its upstream state is owned"
        File = "implementation\src\profiles\ERC3643TrustAdapter.sol"
        Old = "        _requireOwnedUpstreamState(bytes32(0), account);"
        New = ""
        ExpectedOccurrences = 1
        Contract = "ERC3643ProfileUnitTest"
        Test = "testDriftedUpstreamStateFailsClosedOnEveryTouchedAccount"
    },
    @{
        Id = "MUT-51-ERC3643-RESYNC-RAISES-FROZEN"
        Fault = "Never raise the upstream frozen amount toward the owned target"
        File = "implementation\src\profiles\ERC3643TrustAdapter.sol"
        Old = "if (expected > current) {"
        New = "if (false) {"
        ExpectedOccurrences = 1
        Contract = "ERC3643ProfileTrexFixtureTest"
        Test = "testInboundGrowthIsRefrozenByPermissionlessResynchronisation"
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
        Get-ChildItem -LiteralPath (Join-Path $repoRoot "implementation\src") -File -Recurse
        Get-ChildItem -LiteralPath (Join-Path $repoRoot "implementation\test") -File -Recurse
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
    if ($mutation.ContainsKey("FirstOnly")) {
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
