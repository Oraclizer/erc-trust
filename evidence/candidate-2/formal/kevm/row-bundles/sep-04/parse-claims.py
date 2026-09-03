#!/usr/bin/env python3
"""Parse SEP-04 claims through K's dry-run front end without starting a backend."""

import argparse
import hashlib
import json
from pathlib import Path

import kevm_pyk
from pyk.kast.outer import KClaim
from pyk.ktool.kprove import KProve


ROW = Path(__file__).resolve().parent
REPOSITORY = ROW.parents[3]
POSITIVE_MODULE = "TRUST-SEP-04-RECEIPT-PREIMAGE-STORAGE-RETURN-FINAL-EVENT-SPEC"
CONTROL_MODULE = "TRUST-SEP-04-MUTANT-EVENT-TOPIC-CONTROL-SPEC"


def canonical_sha256(claim: KClaim) -> str:
    encoded = json.dumps(claim.to_dict(), sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--definition", required=True, type=Path)
    parser.add_argument("--positive", default=ROW / "claim.k", type=Path)
    parser.add_argument("--control", default=ROW / "mutant-control-claim.k", type=Path)
    parser.add_argument(
        "--role",
        choices=("all", "positive", "control"),
        default="all",
        help="parse both claims, or one claim in an isolated dry-run process",
    )
    args = parser.parse_args()

    definition = args.definition.resolve()
    if not (definition / "definition.kore").is_file():
        raise SystemExit(f"compiled definition missing: {definition}")

    kprove = KProve(definition_dir=definition)
    kproj_root = Path(kevm_pyk.__file__).resolve().parent / "kproj"
    kevm_include = kproj_root / "evm-semantics"
    plugin_include = kproj_root / "plugin"
    if not (kevm_include / "edsl.md").is_file():
        raise SystemExit(f"pinned KEVM include missing: {kevm_include}")
    claim_inputs = (
        ("positive-and-negative-detector", args.positive.resolve(), POSITIVE_MODULE),
        ("mutant-executable-control", args.control.resolve(), CONTROL_MODULE),
    )
    if args.role == "positive":
        claim_inputs = claim_inputs[:1]
    elif args.role == "control":
        claim_inputs = claim_inputs[1:]

    parsed = []
    for role, path, module in claim_inputs:
        claims = kprove.get_claims(
            spec_file=path,
            spec_module_name=module,
            include_dirs=(REPOSITORY / "formal" / "kevm", ROW, kevm_include, plugin_include),
            include_dependencies=False,
        )
        if len(claims) != 1:
            raise SystemExit(f"{role}: expected exactly one claim, got {len(claims)}")
        claim = claims[0]
        parsed.append(
            {
                "role": role,
                "path": path.relative_to(REPOSITORY).as_posix(),
                "module": module,
                "label": claim.label,
                "canonicalKastSha256": canonical_sha256(claim),
            }
        )

    print(
        json.dumps(
            {
                "status": "PASS_PARSE_ONLY",
                "backendStarted": False,
                "proofAttempted": False,
                "selectedRole": args.role,
                "definition": str(definition),
                "claims": parsed,
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
