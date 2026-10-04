#!/usr/bin/env python3
"""Generate the review input seal for the current TRUST 1.2 development tranche."""
from pathlib import Path
import hashlib
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
EXACT = [
    "scripts/lib/trust12-policy.mjs",
    "scripts/verify-trust12-policy.mjs",
    "scripts/test-trust12-policy.mjs",
    "evidence/claim-matrix.md",
    "evidence/known-limitations.md",
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
    "scripts/proof-ci.mjs",
    "scripts/run-proof-ci.sh",
    "scripts/test-proof-ci.mjs",
    "scripts/lib/runtime-bundles.mjs",
    "scripts/test-trust12-required.mjs",
    "scripts/test-full-source-admission.py",
    "scripts/test-model-source-reception.py",
    "scripts/test-original-binding-meaning.py",
    "scripts/trust12/verify_original_binding_meaning_v1.py",
    "evidence/trust12/runtime-link/original-binding-meaning-checkpoint-v1.json",
    "scripts/test-assess-call-reception.py",
    "scripts/trust12/verify_assess_call_reception_v1.py",
    "evidence/trust12/runtime-link/assess-call-reception-checkpoint-v1.json",
    "scripts/test-native-supply-direction-negative.py",
    "scripts/trust12/verify_native_supply_direction_negative_v1.py",
    "evidence/trust12/runtime-link/native-supply-direction-negative-checkpoint-v1.json",
    "scripts/test-dependency-call-provenance.py",
    "scripts/trust12/verify_dependency_call_provenance_v1.py",
    "evidence/trust12/runtime-link/dependency-call-provenance-checkpoint-v1.json",
    "scripts/test-second-freeze-rejection.py",
    "scripts/trust12/verify_second_freeze_rejection_v1.py",
    "evidence/trust12/runtime-link/second-freeze-rejection-checkpoint-v1.json",
    "scripts/test-malformed-aligned-gate.py",
    "scripts/trust12/verify_malformed_aligned_gate_v1.py",
    "evidence/trust12/runtime-link/malformed/aligned-gate-checkpoint-v1.json",
    "scripts/trust12/verify_malformed_guard_mutants_v1.py",
    "scripts/test-malformed-guard-mutants.py",
    "scripts/trust12/tail-preparation/run_malformed_probe_v2.py",
    "evidence/trust12/runtime-link/tail-preparation/malformed-probe-mutants-v1.json",
    "evidence/trust12/runtime-link/tail-preparation/malformed-guard-mutants-checkpoint-v1.json",
    "scripts/test-certificate-registry.py",
    "scripts/trust12/verify_certificate_registry_v1.py",
    "scripts/trust12/tail-preparation/certificate_registry_v2.py",
    "scripts/trust12/tail-preparation/kore_accounts.py",
    "scripts/trust12/tail-preparation/test_certificate_registry_v2.py",
    "evidence/trust12/runtime-link/tail-preparation/certificate-registry-schema-v2.json",
    "evidence/trust12/runtime-link/tail-preparation/certificate-registry-checkpoint-v1.json",
    "scripts/test-route-inventory.py",
    "scripts/trust12/verify_route_inventory_v1.py",
    "scripts/trust12/tail-preparation/route_inventory_v2.py",
    "scripts/trust12/tail-preparation/run_route_disposition_tests.py",
    "scripts/trust12/tail-preparation/test_route_inventory_v2.py",
    "scripts/trust12/tail-preparation/route-dispositions/HookRouteDispositions.t.sol",
    "scripts/trust12/tail-preparation/route-dispositions/NativeAllowanceRoutes.t.sol",
    "spec/decisions/14-hook-route-classes.md",
    "spec/decisions/15-route-dispositions.md",
    "spec/generated/hook-route-classes-v1.json",
    "evidence/trust12/runtime-link/tail-preparation/route-dispositions-v1.json",
    "evidence/trust12/runtime-link/tail-preparation/route-inventory-checkpoint-v1.json",
    "scripts/test-typed-failure-binding.py",
    "scripts/trust12/verify_typed_failure_binding_v1.py",
    "scripts/trust12/tail-preparation/typed_failure_report.py",
    "scripts/trust12/tail-preparation/run_typed_failure_probe.py",
    "scripts/trust12/tail-preparation/code_identity_v2.py",
    "scripts/trust12/tail-preparation/test_typed_failure_binding.py",
    "scripts/trust12/tail-preparation/typed-failure-probe/TypedFailureProbeCore.sol",
    "scripts/trust12/tail-preparation/typed-failure-probe/NativeTypedFailureProbe.t.sol",
    "scripts/trust12/tail-preparation/typed-failure-probe/PartialTypedFailureProbe.t.sol",
    "scripts/trust12/tail-preparation/typed-failure-probe/HookTypedFailureProbe.t.sol",
    "evidence/trust12/runtime-link/tail-preparation/typed-failure-probe-mutants-v1.json",
    "evidence/trust12/runtime-link/tail-preparation/typed-failure-checkpoint-v1.json",
    "evidence/trust12/runtime-link/tail-preparation/tail-obligations-v1.json",
    "scripts/test-primitive-source-controls.py",
    "scripts/trust12/verify_primitive_source_controls_v1.py",
    "evidence/trust12/runtime-link/primitive-source-controls-checkpoint-v1.json",
    "scripts/test-received-transaction-controls.py",
    "scripts/trust12/verify_received_transaction_controls_v1.py",
    "evidence/trust12/runtime-link/received-transaction-controls-checkpoint-v1.json",
    "scripts/trust12/verify_model_source_reception_v1.py",
    "evidence/trust12/runtime-link/model-source-reception-checkpoint-v1.json",
    "scripts/trust12/verify_full_source_admission_v1.py",
    "scripts/trust12/verify_received_valuation_current_v1.py",
    "evidence/trust12/runtime-link/native-full-source-admission-checkpoint-v1.json",
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
