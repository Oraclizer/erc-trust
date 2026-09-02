# Candidate 2 defect: reversal accepted on a terminal case

Reproduced on the candidate 2 source (integration branch head
`417c993e359ed02c18ec636353e4919bf38461eb`, whose `implementation/` tree is the
candidate 2 tree) with Foundry 1.7.1 and Solidity 0.8.36 on 2026-09-02.

The scenario: a `FREEZE` opens case C; a direct `CONFISCATE` filed against the
same case C is accepted and makes C terminal; the `UNFREEZE` of the freeze is
then accepted although its case is terminal, because the version 1 reversal
path checked only the action lifecycle and never the case.

Kernel version 2 closes both doors: a disposition against an open overlay case
is rejected with reason 10 (`CT-14`), and every action or reversal on a
terminal case reverts with `TrustTerminal` (`CT-15`). The successor test
`testDispositionOnOpenOverlayCaseIsRejectedAndTerminalCasesRejectReversals`
in `implementation/test/TrustActions.unit.t.sol` asserts both.

## Test source (compiled against the candidate 2 tree, not committed there)

```solidity
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {TrustTestBase} from "./TrustTestBase.t.sol";
import {TrustTypes} from "../src/TrustTypes.sol";

contract Candidate2FreezeConfiscateUnfreezeRepro is TrustTestBase {
    function testFreezeThenSameCaseDirectConfiscateThenUnfreezeIsAccepted() external {
        TrustTypes.ActionRequest memory freeze = _request(TrustTypes.ActionKind.FREEZE, 1, 5 ether);
        token.executeRegulatoryAction(freeze);
        require(token.getFrozenTokens(address(this)) == 5 ether, "freeze applied");

        TrustTypes.ActionRequest memory confiscate = _request(TrustTypes.ActionKind.CONFISCATE, 2, 1 ether);
        confiscate.caseId = freeze.caseId;
        confiscate.actionId = token.deriveActionId(confiscate);
        (bool confiscateOk,) = address(token).call(abi.encodeCall(token.executeRegulatoryAction, (confiscate)));
        require(confiscateOk, "direct CONFISCATE accepted against the open FREEZE case");
        require(token.caseTerminal(freeze.caseId), "case is terminal after the disposition");

        TrustTypes.ReversalRequest memory unfreeze = _reversal(freeze.actionId, TrustTypes.ReversalKind.UNFREEZE, 3);
        (bool unfreezeOk,) = address(token).call(abi.encodeCall(token.executeRegulatoryReversal, (unfreeze)));
        require(unfreezeOk, "UNFREEZE accepted although the case is terminal (defect reproduced)");
        require(token.getFrozenTokens(address(this)) == 0, "frozen target restored after terminal-case unfreeze");
        require(token.caseTerminal(freeze.caseId), "case still terminal");
    }
}
```

## Foundry output

```text
Ran 1 test for implementation/test/Candidate2Repro.t.sol:Candidate2FreezeConfiscateUnfreezeRepro
[PASS] testFreezeThenSameCaseDirectConfiscateThenUnfreezeIsAccepted() (gas: 1569392)
Suite result: ok. 1 passed; 0 failed; 0 skipped
```

The test passing is the defect: every `require` that documents the accepted
disposition and the accepted reversal held on the candidate 2 code.
