#!/usr/bin/env python3
"""Generate the review input seal for the current TRUST 1.2 development tranche."""
from pathlib import Path
import hashlib
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
EXACT = [
    "implementation/kontrol/trust12/TrustTokenDeferredSymbolicKontrolTest.t.sol",
    "scripts/veri_dependency.py",
    "scripts/run-veri-native.py",
    "scripts/run-veri-profiles.py",
    "scripts/run-veri-mutations.py",
    "scripts/replay-veri-mutants.py",
    "scripts/run-veri-observation-controls.py",
    "scripts/record-veri-observations.py",
    "scripts/test-veri-dependency.py",
    "scripts/run-deferred-symbolic.py",
    "scripts/prepare-native-storage-predicates.py",
    "scripts/run-veri-symbolic-summaries.py",
    "scripts/capture-isabelle-local-inputs.mjs",
    "scripts/generate-trust12-proof-audit.py",
    "scripts/lib/runtime-bundles.mjs",
    "scripts/test-trust12-required.mjs",
    "scripts/verify-trust12-required.mjs",
    "scripts/lib/local-evidence.mjs",
    "scripts/lib/formal-inputs.mjs",
    "scripts/record-foundry-results-v3.mjs",
    "scripts/record-isabelle-results-v3.mjs",
    "scripts/record-trust12-deterministic.mjs",
    "scripts/record-trust12-model-results.mjs",
    "scripts/generate-runtime-binding-v3.mjs",
    "CHANGELOG.md",
    "scripts/verify-trust12-evidence-reuse.mjs",
    "scripts/test-trust12-evidence-reuse.mjs",
    "scripts/verify-current-profile-release-v3.mjs",
    "scripts/verify-obligation-ledger-v3.mjs",
    "scripts/verify-runtime-binding-v3.mjs",
    ".github/workflows/ci.yml",
    ".github/workflows/proofs.yml",
    "FORMAL_VERIFICATION.md",
    "docs/PROFILES.md",
    "formal/isabelle/ERC_TRUST/Proof_Audit.thy",
    "formal/isabelle/ERC_TRUST/ROOT",
    "formal/isabelle/ERC_TRUST/TRUST_Transaction_Refinement.thy",
    "formal/isabelle/ERC_TRUST/evidence/model-verification/run-trust-closure.ps1",
    "formal/isabelle/ROOTS",
    "formal/isabelle/TRUST12_OBSTRUCTIONS/ROOT",
    "formal/isabelle/TRUST12_OBSTRUCTIONS/TRUST12_Obstruction_Proof_Audit.thy",
    "formal/isabelle/TRUST12_OBSTRUCTIONS/TRUST_Accounting_Invariant_Obstruction.thy",
    "formal/isabelle/TRUST12_OBSTRUCTIONS/TRUST_State_Invariants.thy",
    "foundry.toml",
    "implementation/kontrol/trust12/TrustTokenSymbolicKontrolTest.t.sol",
    "implementation/src/profiles/ERC3643HookAdapter.sol",
    "implementation/src/profiles/ERC3643HookCompliance.sol",
    "implementation/src/profiles/ERC3643HookDeployment.sol",
    "implementation/src/profiles/ERC3643HookFactory.sol",
    "implementation/src/profiles/ERC3643HookGovernor.sol",
    "implementation/src/profiles/ERC3643TrustAdapter.sol",
    "implementation/src/profiles/ProfileGovernor.sol",
    "implementation/test/ERC3643HookTrexIntegration.t.sol",
    "scripts/check-hook-consumer-removal.py",
    "scripts/check-trust12-runtime-identity.py",
    "scripts/generate-trust12-input-seal.py",
    "scripts/prepare-trex-integration.py",
    "scripts/verify-trust12-evidence.py",
]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    evidence = sorted(
        path.relative_to(ROOT).as_posix()
        for path in (ROOT / "evidence/trust12").glob("*")
        if path.is_file() and path.name != "input-seal.json"
    )
    child_theories = [path.relative_to(ROOT).as_posix()
                      for path in (ROOT / "formal/isabelle/TRUST12_OBSTRUCTIONS").glob("*.thy")]
    paths = sorted(set(EXACT + evidence + child_theories))
    missing = [path for path in paths if not (ROOT / path).is_file()]
    if missing:
        raise RuntimeError("missing sealed inputs: " + ", ".join(missing))
    report = {
        "schema": "trust12-input-seal-v2",
        "baselineCommit": "2545efa64289ad82fe3ad8a99e5dfad01ff92c10",
        "branch": "trust-1-2-enhancement",
        "files": [{"path": path, "sha256": digest(ROOT / path)} for path in paths],
        "nonclaim": "This seals one local development tranche. It is not a deployment, release, conformance approval, or end-to-end refinement result.",
    }
    encoded = json.dumps(report, indent=2) + "\n"
    if "--write" in sys.argv:
        (ROOT / "evidence/trust12/input-seal.json").write_text(encoded, encoding="utf8", newline="\n")
    print(encoded, end="")


if __name__ == "__main__":
    main()
