#!/usr/bin/env python3
"""Controls of certificate registry v2 on a synthetic product and evidence root (no private file is read).

The fixture is a complete registry: twenty-seven closed cells, a malformed branch per profile, worlds that hold
the executed runtime set of each profile, kernel stage input bindings, one world named only by a KORE export
with a quoted reason, and two certificates whose acceptance comes from a stored proof graph. Every control
changes one thing and checks that the matching check fails or stays incomplete and that closure mode refuses.
"""
from __future__ import annotations

import contextlib
import copy
import hashlib
import io
import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

import certificate_registry_v2 as registry  # noqa: E402
import kore_accounts  # noqa: E402
from tail_common import OPERATIONS, PROFILES, PreparationError, load_json, schema_errors  # noqa: E402

CONTRACTS = {"Native": ["TrustToken"], "Partial": ["ERC3643TrustAdapter", "ProfileGovernor"],
             "Hook": ["ERC3643HookAdapter", "ERC3643HookGovernor", "ERC3643HookCompliance", "ERC3643HookFactory"]}
ENDPOINTS = {"Native": "TrustToken", "Partial": "ERC3643TrustAdapter", "Hook": "ERC3643HookAdapter"}
CATALOG = {"Native": ["empty-calldata", "unknown-selector"], "Partial": ["empty-calldata"], "Hook": ["empty-calldata"]}
BASE_ACCOUNT = {"Native": 1000, "Partial": 2000, "Hook": 3000}
RANGE = (8, 40)
REASON_TEXT = "The fixture call reads a snapshot inside the call, and the kernel record uses the world before it."
QUOTE = "reads a snapshot inside the call"
COLON = ":" if os.name != "nt" else "\uf03a"
APR_FIELDS = {"proofId": "proofId", "proofSha256": "proofJson.sha256", "kcfgSha256": "kcfg.sha256"}
APR_ACCEPTANCE = {"passed": True, "failed": False, "admitted": False, "circularity": False,
                  "pendingNodes": [], "failingNodes": []}
SELECTION_PROOF = {"proofId": "id", "proofSha256": "proofJsonSha256", "kcfgSha256": "kcfgSha256"}


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def template(contract: str) -> bytes:
    code = bytearray((hashlib.sha256(contract.encode()).digest() * 4)[:100])
    code[RANGE[0]:RANGE[1]] = bytes(RANGE[1] - RANGE[0])
    return bytes(code)


def deployed(contract: str, salt: bytes = b"unit") -> bytes:
    code = bytearray(template(contract))
    code[RANGE[0]:RANGE[1]] = hashlib.sha256(salt + contract.encode()).digest()
    return bytes(code)


def kore_bytes(data: bytes) -> str:
    return "".join(chr(b) if 0x20 <= b < 0x7F and chr(b) not in '"\\' else f"\\x{b:02x}" for b in data)


def account_item(identifier: int, code: bytes | None) -> str:
    key = f"Lbl'-LT-'acctID'-GT-'{{}}(\\dv{{SortInt{{}}}}(\"{identifier}\"))"
    cell = ("VarCODE:SortAccountCode{}" if code is None else
            f"inj{{SortBytes{{}}, SortAccountCode{{}}}}(\\dv{{SortBytes{{}}}}(\"{kore_bytes(code)}\"))")
    account = (f"Lbl'-LT-'account'-GT-'{{}}({key},Lbl'-LT-'balance'-GT-'{{}}(\\dv{{SortInt{{}}}}(\"0\")),"
               f"Lbl'-LT-'code'-GT-'{{}}({cell}))")
    return f"LblAccountCellMapItem{{}}({key},{account})"


def accounts_cell(accounts: list[tuple[int, bytes | None]]) -> str:
    items = [account_item(identifier, code) for identifier, code in accounts]
    text = items[-1]
    for item in reversed(items[:-1]):
        text = f"Lbl'Unds'AccountCellMap'Unds'{{}}({item},{text})"
    return text


def frame(identifier: int) -> str:
    return f"\\dv{{SortInt{{}}}}(\"{identifier}\")"


def unit(profile: str) -> list[tuple[int, bytes | None]]:
    base = BASE_ACCOUNT[profile]
    runtime = [(base + index, deployed(name)) for index, name in enumerate(CONTRACTS[profile])
               if name != "ERC3643HookFactory"]
    return runtime + [(base + 50, hashlib.sha256(profile.encode()).digest() * 2), (base + 60, b"\x60\x80")]


def graph(admitted: bool = False, extra_leaf: bool = False, terminal_leaf: bool = False,
          subproofs: list | None = None, extra_key: bool = False) -> tuple[dict, dict]:
    nodes, edges = [1, 2, 3, 4], [{"source": 1, "target": 3}, {"source": 3, "target": 4}]
    covers = [{"source": 4, "target": 2}]
    terminal = [2, 4]
    if extra_leaf:
        nodes.append(5)
        edges.append({"source": 3, "target": 5})
    if terminal_leaf:
        covers = []
    proof = {"id": None, "type": "APRProof", "init": 1, "target": 2, "terminal": terminal, "admitted": admitted,
             "circularity": False, "subproof_ids": subproofs or [], "node_refutations": {}, "bounded": [], "logs": {}}
    kcfg = {"next": len(nodes) + 1, "nodes": nodes, "edges": edges, "covers": covers, "vacuous": [], "stuck": []}
    if extra_key:
        kcfg["splits"] = []
        kcfg["unknownPart"] = []
    return proof, kcfg


class Fixture:
    def __init__(self) -> None:
        self.base = Path(tempfile.mkdtemp(prefix="registry-v2-test-"))
        self.product, self.evidence = self.base / "product", self.base / "evidence"
        self.write_product()
        self.locators = self.write_evidence()

    # Synthetic product -------------------------------------------------------------------------
    def write_product(self) -> None:
        profiles = {}
        for profile in PROFILES:
            runtimes = [{"contract": name, "runtimeTemplate": {"sha256": digest(template(name)), "bytes": 100},
                         "immutableRanges": [list(RANGE)]} for name in CONTRACTS[profile]]
            profiles[profile] = {"profileIndex": f"Runtime_{profile}", "endpoint": ENDPOINTS[profile],
                                 "identityRootSha256": digest(profile.encode()), "runtimes": runtimes}
        self.put(self.product / registry.CODE_IDENTITY_PATH, {"profiles": profiles})
        self.put(self.product / registry.MALFORMED_CATALOG_PATH,
                 {"profiles": [{"profile": profile.lower(), "slugs": CATALOG[profile]} for profile in PROFILES]})
        self.reason_path = "evidence/trust12/runtime-link/reason-record.json"
        self.put(self.product / self.reason_path, {"identityBoundary": REASON_TEXT})

    # Synthetic evidence ------------------------------------------------------------------------
    def put(self, path: Path, value) -> str:
        path.parent.mkdir(parents=True, exist_ok=True)
        data = value if isinstance(value, bytes) else (value if isinstance(value, str) else json.dumps(value)).encode("utf-8")
        path.write_bytes(data)
        return digest(data)

    def evidence_put(self, relative: str, value) -> str:
        return self.put(self.evidence / relative.replace(":", COLON), value)

    def write_world(self, relative: str, accounts, frame_id: int) -> str:
        sha = self.evidence_put(relative + "/accounts.kore", accounts_cell(accounts))
        self.evidence_put(relative + "/frameid.kore", frame(frame_id))
        return sha

    def write_evidence(self) -> dict:
        self.kernel_sha = self.evidence_put("cells/Run01/result.json", {"status": "PASS_KERNEL_CHECKED_FIXTURE"})
        rows = [{"id": f"cell/{profile}/{operation}", "status": "CLOSED",
                 "evidence": {"positiveActivation": [{"kind": "kernel", "root": "cells", "run": "Run01",
                                                      "theory": "Fixture", "resultSha256": self.kernel_sha}]}}
                for profile in PROFILES for operation in OPERATIONS]
        self.evidence_put("ledger/obligation-ledger.json", {"rows": rows})
        self.batches = {profile: {"certificates": []} for profile in PROFILES}
        self.stages = {profile: {"schema": "fixture-stage-input-v1", "session": f"FIXTURE_{profile.upper()}_STAGE",
                                 "cells": []} for profile in PROFILES}
        self.export = {"schema": "fixture-kore-export-v1", "snapshots": {}}
        cells, malformed = [], []
        for profile in PROFILES:
            for operation in OPERATIONS:
                specs = []
                for outcome, word in (("applied", "applied"), ("not-applied", "rejected")):
                    slug = f"{operation.lower()}-{word}"
                    if profile == "Native" and operation == "LIQUIDATE":
                        specs.append(self.stored_proof_certificate(slug, outcome))
                    else:
                        specs.append(self.batch_certificate(profile, slug, outcome, operation))
                cells.append({"profile": profile, "operation": operation, "certificates": specs})
            malformed.append({"profile": profile, "certificates": [
                self.batch_certificate(profile, slug, "malformed", None) for slug in CATALOG[profile]]})
        self.write_shared()
        return {"schema": "trust12-tail-preparation-certificate-locators-v2", "ledger": "ledger/obligation-ledger.json",
                "cells": cells, "malformed": malformed}

    def write_shared(self) -> None:
        for profile in PROFILES:
            self.evidence_put(f"batch/{profile}/result.json", self.batches[profile])
            self.evidence_put(f"stage/{profile}/input-binding.json", self.stages[profile])
        self.evidence_put("export/result.json", self.export)

    def world(self, profile: str, folder: str, title: str) -> dict:
        endpoint = BASE_ACCOUNT[profile]
        sha = self.write_world(folder, unit(profile), endpoint)
        self.stages[profile]["cells"].append({"title": title, "kore": {"path": folder + "/accounts.kore", "sha256": sha}})
        return {"role": "entry", "accounts": folder + "/accounts.kore", "frame": folder + "/frameid.kore",
                "endpointRecord": {"path": folder + "/selection.json", "pointer": "/endpoint"},
                "consumers": [{"kind": "KERNEL_STAGE_INPUT", "path": f"stage/{profile}/input-binding.json",
                               "array": "/cells", "match": {"title": title}, "field": "kore"}]}

    def batch_certificate(self, profile: str, slug: str, outcome: str, operation: str | None) -> dict:
        folder = f"batch/{profile}/certificates/{slug}"
        proof_id = f"fixture%{profile}.{slug}():0"
        record = {"slug": slug, "proofId": proof_id, "proofJson": {"sha256": digest((proof_id + "p").encode())},
                  "kcfg": {"sha256": digest((proof_id + "k").encode())}, **APR_ACCEPTANCE}
        if operation is not None:
            record.update(operation=operation, outcome="applied" if outcome == "applied" else "rejected")
        self.batches[profile]["certificates"].append(record)
        self.evidence_put(folder + "/selection.json", {
            "endpoint": BASE_ACCOUNT[profile],
            "proof": {"id": proof_id, "proofJsonSha256": record["proofJson"]["sha256"], "kcfgSha256": record["kcfg"]["sha256"]}})
        spec = {"outcome": outcome, "form": "APR_PROOF",
                "source": {"path": f"batch/{profile}/result.json", "array": "/certificates", "match": {"slug": slug}},
                "fields": APR_FIELDS, "acceptance": {"fields": APR_ACCEPTANCE},
                "corroborate": [{"reference": {"path": folder + "/selection.json", "pointer": "/proof"},
                                 "fields": SELECTION_PROOF}],
                "execution": {"preWorlds": [self.world(profile, folder, slug + "-entry")]}}
        if outcome == "malformed":
            spec["slug"] = slug
        if profile == "Native" and slug == "freeze-rejected":
            spec["execution"]["preWorlds"].insert(0, self.export_world(folder + "/inside"))
        return spec

    def export_world(self, folder: str) -> dict:
        sha = self.write_world(folder, unit("Native"), BASE_ACCOUNT["Native"])
        self.export["snapshots"]["inside"] = {"accounts": {"path": folder + "/accounts.kore", "sha256": sha}}
        return {"role": "inside-call", "accounts": folder + "/accounts.kore", "frame": folder + "/frameid.kore",
                "consumers": [{"kind": "KORE_EXPORT", "path": "export/result.json",
                               "pointer": "/snapshots/inside/accounts"}],
                "exportOnly": {"reason": "The kernel record uses the world before the call.", "quote": QUOTE,
                               "source": {"path": self.reason_path, "pointer": "/identityBoundary"}}}

    def write_stored_proof(self, slug: str, **graph_options) -> None:
        """Write the stored proof and graph of a certificate and the hashes that its extraction record holds."""
        folder = f"liquidate/{slug}"
        proof_id = f"fixture%Native.{slug}():0"
        proof, kcfg = graph(**graph_options)
        proof["id"] = proof_id
        kcfg["edges"][0]["rules"] = [slug]
        proof_sha = self.evidence_put(f"{folder}/proofs/{proof_id}/proof.json", proof)
        kcfg_sha = self.evidence_put(f"{folder}/proofs/{proof_id}/kcfg/kcfg.json", kcfg)
        self.evidence_put(folder + "/selection.json", {
            "endpoint": BASE_ACCOUNT["Native"],
            "proof": {"id": proof_id, "type": "APRProof", "admitted": False, "proofJsonSha256": proof_sha, "kcfgSha256": kcfg_sha}})

    def stored_proof_certificate(self, slug: str, outcome: str) -> dict:
        folder = f"liquidate/{slug}"
        proof_id = f"fixture%Native.{slug}():0"
        self.write_stored_proof(slug)
        return {"outcome": outcome, "form": "APR_PROOF", "source": {"path": folder + "/selection.json", "pointer": "/proof"},
                "fields": {"proofId": "id", "proofSha256": "proofJsonSha256", "kcfgSha256": "kcfgSha256"},
                "acceptance": {"fields": APR_ACCEPTANCE,
                               "storedProof": {"proof": f"{folder}/proofs/{proof_id}/proof.json",
                                               "kcfg": f"{folder}/proofs/{proof_id}/kcfg/kcfg.json"}},
                "execution": {"preWorlds": [self.world("Native", folder, slug + "-entry")]}}

    # Mutations ---------------------------------------------------------------------------------
    def spec(self, locators: dict, key: str) -> dict:
        profile, operation, outcome = key.split("/")
        if operation == "MALFORMED":
            branch = next(item for item in locators["malformed"] if item["profile"] == profile)
            return next(item for item in branch["certificates"] if item["slug"] == outcome)
        cell = next(item for item in locators["cells"] if item["profile"] == profile and item["operation"] == operation)
        return next(item for item in cell["certificates"] if item["outcome"] == outcome)

    def rewrite_world(self, key: str, accounts, frame_id: int | None = None, world: int = -1, rebind: bool = True) -> None:
        """Replace the recorded world of a certificate and, unless told otherwise, the consumer hash that names it."""
        spec = self.spec(self.locators, key)["execution"]["preWorlds"][world]
        profile = key.split("/")[0]
        text = accounts if isinstance(accounts, str) else accounts_cell(accounts)
        sha = self.evidence_put(spec["accounts"], text)
        if frame_id is not None:
            self.evidence_put(spec["frame"], frame(frame_id))
        if rebind:
            for item in self.stages[profile]["cells"]:
                if item["kore"]["path"] == spec["accounts"]:
                    item["kore"]["sha256"] = sha
            for item in self.export["snapshots"].values():
                if item["accounts"]["path"] == spec["accounts"]:
                    item["accounts"]["sha256"] = sha
            self.write_shared()

    def close(self) -> None:
        shutil.rmtree(self.base, ignore_errors=True)


class RegistryTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = Fixture()

    def tearDown(self) -> None:
        self.fixture.close()

    def build(self, locators: dict | None = None, mode: str = "dry-run") -> dict:
        source = {"sha256": "0" * 64, "bytes": 1}
        return registry.build(self.fixture.evidence, locators or self.fixture.locators, mode, source, self.fixture.product)

    def status(self, result: dict, name: str) -> str:
        return next(item["status"] for item in result["checks"] if item["id"] == name)

    def assert_refused(self, name: str, expected: str, locators: dict | None = None) -> dict:
        result = self.build(locators)
        self.assertEqual(self.status(result, name), expected, json.dumps(result["checks"], indent=1)[:2000])
        self.assertNotEqual(result["status"], "REGISTRY_COMPLETE_CANDIDATE")
        with self.assertRaises(PreparationError):
            self.build(locators, mode="closure")
        return result

    def mutated(self) -> dict:
        return copy.deepcopy(self.fixture.locators)


class PositiveTest(RegistryTestCase):
    def test_complete_registry_closes(self) -> None:
        result = self.build(mode="closure")
        self.assertEqual(result["status"], "REGISTRY_COMPLETE_CANDIDATE")
        self.assertEqual({item["id"]: item["status"] for item in result["checks"]},
                         {item["id"]: "PASS" for item in result["checks"]})
        partition = result["partition"]
        self.assertEqual((partition["boundCells"], partition["registeredCertificates"], partition["executedCodeMatches"]),
                         (27, 58, 58))
        self.assertEqual((partition["recordedWorlds"], partition["worldsNamedByKernelStageInputs"],
                          partition["worldsNamedOnlyByKoreExports"]), (59, 58, 1))
        self.assertEqual(partition["acceptanceMethods"], {"RECORDED_FIELDS": 56, "STORED_PROOF_GRAPH": 2})
        factory = result["profiles"]["Hook"]["deploymentOnlyRuntimes"]["ERC3643HookFactory"]
        self.assertEqual((factory["accountsInRecordedWorlds"], factory["assumption"]), (0, "A-DEPLOYMENT"))
        self.assertEqual(sorted(result["profiles"]["Hook"]["executedRuntimes"]),
                         ["ERC3643HookAdapter", "ERC3643HookCompliance", "ERC3643HookGovernor"])
        self.assertEqual(result["profiles"]["Hook"]["unboundAccountCounts"], [2])
        self.assertEqual(sorted(result["retainedAssumptions"]), ["A-DEPLOYMENT", "A-EXTERNAL"])
        self.assertEqual(schema_errors(result, load_json(registry.SCHEMA)), [])

    def test_build_is_deterministic(self) -> None:
        self.assertEqual(json.dumps(self.build(), sort_keys=True), json.dumps(self.build(), sort_keys=True))

    def test_inside_immutable_change_still_matches(self) -> None:
        accounts = unit("Partial")
        accounts[0] = (accounts[0][0], deployed("ERC3643TrustAdapter", b"another deployment"))
        self.fixture.rewrite_world("Partial/SEIZE/applied", accounts)
        self.assertEqual(self.build(mode="closure")["status"], "REGISTRY_COMPLETE_CANDIDATE")

    def test_command_line_build_and_verify(self) -> None:
        locators = self.fixture.base / "locators.json"
        locators.write_text(json.dumps(self.fixture.locators), encoding="utf-8")
        output = self.fixture.base / "out" / "registry.json"
        arguments = ["--evidence", str(self.fixture.evidence), "--locators", str(locators),
                     "--product-root", str(self.fixture.product)]
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(registry.main(["build", *arguments, "--output", str(output), "--mode", "closure"]), 0)
            self.assertEqual(registry.main(["verify", *arguments, "--registry", str(output)]), 0)
        self.assertEqual(load_json(output)["inputs"]["locators"]["sha256"], registry.locator_identity(locators)["sha256"])
        with self.assertRaisesRegex(PreparationError, "already exists"):
            registry.main(["build", *arguments, "--output", str(output)])
        document = load_json(output)
        document["certificates"][0]["execution"]["status"] = "MISMATCH"
        output.write_text(json.dumps(document), encoding="utf-8")
        with self.assertRaisesRegex(PreparationError, "recomputation differs"):
            registry.main(["verify", *arguments, "--registry", str(output)])


class ExecutedCodeTest(RegistryTestCase):
    def endpoint_code(self, transform) -> list:
        accounts = unit("Native")
        accounts[0] = (accounts[0][0], transform(accounts[0][1]))
        return accounts

    def test_byte_outside_immutable_ranges(self) -> None:
        for offset in (0, RANGE[1], 99):
            with self.subTest(offset=offset):
                self.fixture.rewrite_world("Native/SEIZE/applied", self.endpoint_code(
                    lambda code: code[:offset] + bytes([code[offset] ^ 1]) + code[offset + 1:]))
                self.assert_refused("executed-code-identity", "FAIL")

    def test_length_changes(self) -> None:
        for transform in (lambda code: code[:-1], lambda code: code + b"\x00"):
            self.fixture.rewrite_world("Native/SEIZE/applied", self.endpoint_code(transform))
            self.assert_refused("executed-code-identity", "FAIL")

    def test_symbolic_code(self) -> None:
        accounts = unit("Native")
        accounts[0] = (accounts[0][0], None)
        self.fixture.rewrite_world("Native/SEIZE/applied", accounts)
        result = self.assert_refused("executed-code-identity", "FAIL")
        self.assertIn("0 accounts with the TrustToken template", " ".join(result["checks"][5]["detail"]))

    def test_frame_names_an_absent_account(self) -> None:
        self.fixture.rewrite_world("Native/SEIZE/applied", unit("Native"), frame_id=9)
        result = self.assert_refused("executed-code-identity", "FAIL")
        self.assertIn("frame account differs", " ".join(result["checks"][5]["detail"]))

    def test_unreadable_worlds(self) -> None:
        item = account_item(1000, deployed("TrustToken"))
        for text in (f"Lbl'Unds'AccountCellMap'Unds'{{}}({item},{item})",
                     accounts_cell(unit("Native")).replace("\\x", "\\q", 1)):
            with self.subTest(text=text[:40]):
                self.fixture.rewrite_world("Native/SEIZE/applied", text)
                self.assert_refused("executed-code-identity", "INCOMPLETE")

    def test_missing_runtime_of_the_executed_set(self) -> None:
        accounts = [entry for entry in unit("Hook") if entry[0] != BASE_ACCOUNT["Hook"] + 1]
        self.fixture.rewrite_world("Hook/SEIZE/applied", accounts)
        result = self.assert_refused("executed-code-identity", "FAIL")
        self.assertIn("0 accounts with the ERC3643HookGovernor template", " ".join(result["checks"][5]["detail"]))

    def test_factory_in_a_recorded_world(self) -> None:
        self.fixture.rewrite_world("Hook/SEIZE/applied", unit("Hook") + [(3999, deployed("ERC3643HookFactory"))])
        result = self.assert_refused("executed-code-identity", "FAIL")
        self.assertIn("deployment-only runtime ERC3643HookFactory", " ".join(result["checks"][5]["detail"]))

    def test_duplicate_runtime(self) -> None:
        self.fixture.rewrite_world("Partial/SEIZE/applied", unit("Partial") + [(2999, deployed("ProfileGovernor", b"x"))])
        result = self.assert_refused("executed-code-identity", "FAIL")
        self.assertIn("2 accounts with the ProfileGovernor template", " ".join(result["checks"][5]["detail"]))

    def test_caller_frame_instead_of_the_endpoint(self) -> None:
        self.fixture.rewrite_world("Hook/MALFORMED/empty-calldata", unit("Hook"), frame_id=BASE_ACCOUNT["Hook"] + 60)
        self.assert_refused("executed-code-identity", "FAIL")


class ConsumerTest(RegistryTestCase):
    def test_consumer_records_another_world(self) -> None:
        accounts = unit("Partial")
        accounts[-1] = (accounts[-1][0], b"\x60\x81")
        self.fixture.rewrite_world("Partial/UNFREEZE/applied", accounts, rebind=False)
        self.assert_refused("recorded-worlds-consumed", "FAIL")

    def test_consumer_bound_to_another_title(self) -> None:
        locators = self.mutated()
        self.fixture.spec(locators, "Hook/FREEZE/applied")["execution"]["preWorlds"][0]["consumers"][0]["match"]["title"] = \
            "freeze-rejected-entry"
        self.assert_refused("recorded-worlds-consumed", "FAIL", locators)

    def test_declared_kind_must_match_the_record(self) -> None:
        for key, world, kind in (("Native/SEIZE/applied", 0, "KORE_EXPORT"), ("Native/FREEZE/not-applied", 0, "KERNEL_STAGE_INPUT")):
            with self.subTest(key=key):
                locators = self.mutated()
                self.fixture.spec(locators, key)["execution"]["preWorlds"][world]["consumers"][0]["kind"] = kind
                self.assert_refused("recorded-worlds-consumed", "FAIL", locators)

    def test_world_without_consumer(self) -> None:
        locators = self.mutated()
        self.fixture.spec(locators, "Native/LIQUIDATE/not-applied")["execution"]["preWorlds"][0]["consumers"] = []
        self.assert_refused("recorded-worlds-consumed", "INCOMPLETE", locators)

    def test_export_only_world_needs_a_reason(self) -> None:
        locators = self.mutated()
        self.fixture.spec(locators, "Native/FREEZE/not-applied")["execution"]["preWorlds"][0].pop("exportOnly")
        self.assert_refused("recorded-worlds-consumed", "INCOMPLETE", locators)

    def test_reason_must_be_quoted_from_its_source(self) -> None:
        locators = self.mutated()
        self.fixture.spec(locators, "Native/FREEZE/not-applied")["execution"]["preWorlds"][0]["exportOnly"]["quote"] = \
            "a sentence the source does not contain"
        self.assert_refused("recorded-worlds-consumed", "FAIL", locators)

    def test_reason_on_a_consumed_world(self) -> None:
        locators = self.mutated()
        worlds = self.fixture.spec(locators, "Native/FREEZE/not-applied")["execution"]["preWorlds"]
        worlds[1]["exportOnly"] = copy.deepcopy(worlds[0]["exportOnly"])
        self.assert_refused("recorded-worlds-consumed", "FAIL", locators)

    def test_export_only_world_with_other_code(self) -> None:
        accounts = unit("Native")
        accounts[0] = (accounts[0][0], deployed("TrustToken", b"inside another unit"))
        self.fixture.rewrite_world("Native/FREEZE/not-applied", accounts, world=0)
        self.assert_refused("recorded-worlds-consumed", "FAIL")

    def test_certificate_without_kernel_stage_input(self) -> None:
        locators = self.mutated()
        worlds = self.fixture.spec(locators, "Native/FREEZE/not-applied")["execution"]["preWorlds"]
        del worlds[1]
        result = self.assert_refused("recorded-worlds-consumed", "FAIL", locators)
        self.assertIn("no recorded world of the certificate is named by a kernel stage input",
                      " ".join(result["checks"][6]["detail"]))


class AcceptanceTest(RegistryTestCase):
    def fresh(self) -> None:
        self.fixture.close()
        self.fixture = Fixture()

    def replace_stored(self, slug: str, outcome: str, **options) -> None:
        self.fixture.write_stored_proof(slug, **options)

    def test_recorded_verdict_must_hold(self) -> None:
        self.fixture.batches["Hook"]["certificates"][0]["passed"] = False
        self.fixture.write_shared()
        self.assert_refused("certificate-records-consistent", "FAIL")

    def test_stored_graph_failures(self) -> None:
        for options in ({"extra_leaf": True}, {"terminal_leaf": True}, {"admitted": True}):
            with self.subTest(options=options):
                self.fresh()
                self.replace_stored("liquidate-applied", "applied", **options)
                result = self.assert_refused("certificate-records-consistent", "FAIL")
                graph_record = next(item for item in result["certificates"]
                                    if item["key"] == "Native/LIQUIDATE/applied")["acceptance"]["graph"]
                self.assertEqual(graph_record["verdict"], {"extra_leaf": "PENDING", "terminal_leaf": "FAILED",
                                                           "admitted": "PASSED"}[next(iter(options))])

    def test_stored_graph_unavailable(self) -> None:
        for options in ({"subproofs": ["other"]}, {"extra_key": True}):
            with self.subTest(options=options):
                self.fresh()
                self.replace_stored("liquidate-applied", "applied", **options)
                self.assert_refused("certificate-records-consistent", "INCOMPLETE")

    def test_stored_files_must_match_the_recorded_hashes(self) -> None:
        locators = self.mutated()
        applied = self.fixture.spec(locators, "Native/LIQUIDATE/applied")
        other = self.fixture.spec(locators, "Native/LIQUIDATE/not-applied")
        applied["acceptance"]["storedProof"] = copy.deepcopy(other["acceptance"]["storedProof"])
        self.assert_refused("certificate-records-consistent", "FAIL", locators)

    def test_missing_stored_files(self) -> None:
        locators = self.mutated()
        self.fixture.spec(locators, "Native/LIQUIDATE/applied")["acceptance"]["storedProof"]["proof"] = "liquidate/none/proof.json"
        self.assert_refused("certificate-records-consistent", "INCOMPLETE", locators)

    def test_acceptance_not_recorded(self) -> None:
        locators = self.mutated()
        self.fixture.spec(locators, "Partial/RECOVER/not-applied").pop("acceptance")
        self.assert_refused("certificate-records-consistent", "INCOMPLETE", locators)


class StructureTest(RegistryTestCase):
    def test_removed_cell_certificate(self) -> None:
        locators = self.mutated()
        cell = next(item for item in locators["cells"] if item["profile"] == "Native" and item["operation"] == "SEIZE")
        cell["certificates"] = [item for item in cell["certificates"] if item["outcome"] != "applied"]
        self.assert_refused("cells-agree-with-ledger-and-kernels", "FAIL", locators)

    def test_kernel_result_drift(self) -> None:
        self.fixture.evidence_put("cells/Run01/result.json", {"status": "PASS_KERNEL_CHECKED_FIXTURE", "extra": 1})
        self.assert_refused("cells-agree-with-ledger-and-kernels", "FAIL")

    def test_shared_graph(self) -> None:
        certificates = self.fixture.batches["Partial"]["certificates"]
        certificates[1]["kcfg"]["sha256"] = certificates[0]["kcfg"]["sha256"]
        self.fixture.write_shared()
        self.assert_refused("certificates-distinct", "FAIL")

    def test_repeated_key(self) -> None:
        locators = self.mutated()
        branch = next(item for item in locators["malformed"] if item["profile"] == "Hook")
        branch["certificates"].append(copy.deepcopy(branch["certificates"][0]))
        self.assert_refused("certificate-keys-unique", "FAIL", locators)

    def test_malformed_catalog(self) -> None:
        locators = self.mutated()
        branch = next(item for item in locators["malformed"] if item["profile"] == "Native")
        branch["certificates"] = branch["certificates"][:1]
        self.assert_refused("malformed-registered-as-catalogued", "INCOMPLETE", locators)
        locators = self.mutated()
        next(item for item in locators["malformed"] if item["profile"] == "Native")["certificates"][0]["slug"] = "uncatalogued"
        self.assert_refused("malformed-registered-as-catalogued", "FAIL", locators)

    def test_slug_naming_another_cell(self) -> None:
        record = next(item for item in self.fixture.batches["Hook"]["certificates"] if item["slug"] == "restrict-applied")
        record["operation"] = "SEIZE"
        self.fixture.write_shared()
        self.assert_refused("certificate-records-consistent", "FAIL")

    def test_locator_schema(self) -> None:
        for mutate in (lambda spec: spec["execution"]["preWorlds"][0]["consumers"][0].__setitem__("kind", "OTHER"),
                       lambda spec: spec["execution"]["preWorlds"][0]["consumers"][0].pop("kind"),
                       lambda spec: spec["acceptance"].__setitem__("source", {"path": "x", "pointer": ""})):
            locators = self.mutated()
            mutate(self.fixture.spec(locators, "Native/LIQUIDATE/applied"))
            with self.assertRaisesRegex(PreparationError, "locator file violates its schema"):
                self.build(locators)

    def test_closure_needs_the_locator_identity(self) -> None:
        with self.assertRaisesRegex(PreparationError, "identity of the locator file"):
            registry.build(self.fixture.evidence, self.fixture.locators, "closure", None, self.fixture.product)


class ReaderTest(unittest.TestCase):
    def test_escapes_and_byte_strings(self) -> None:
        self.assertEqual(kore_accounts.decode_string('a\\x41\\u0042\\U00000043\\"'), 'aABC"')
        with self.assertRaises(kore_accounts.KoreError):
            kore_accounts.decode_string("\\q")
        with self.assertRaises(kore_accounts.KoreError):
            kore_accounts.string_bytes(chr(0x100))

    def test_deep_nesting_and_map_keys(self) -> None:
        accounts = [(index, bytes([index % 256]) * 3) for index in range(1, 400)]
        found = kore_accounts.accounts(accounts_cell(accounts))
        self.assertEqual(len(found), 399)
        self.assertEqual(found[7].code, b"\x07\x07\x07")
        wrong = accounts_cell([(5, b"\x01")]).replace('(\\dv{SortInt{}}("5"))', '(\\dv{SortInt{}}("6"))', 1)
        with self.assertRaisesRegex(kore_accounts.KoreError, "names another account"):
            kore_accounts.accounts(wrong)
        self.assertEqual(kore_accounts.frame_account(frame(42)), 42)

    def test_graph_rule(self) -> None:
        proof, kcfg = graph()
        self.assertEqual(registry.graph_verdict(proof, kcfg)["verdict"], "PASSED")
        proof, kcfg = graph(extra_leaf=True)
        self.assertEqual(registry.graph_verdict(proof, kcfg)["pendingNodes"], [5])
        proof, kcfg = graph(terminal_leaf=True)
        self.assertEqual(registry.graph_verdict(proof, kcfg)["failingNodes"], [4])
        proof, kcfg = graph(terminal_leaf=True)
        kcfg["vacuous"] = [4]
        self.assertEqual(registry.graph_verdict(proof, kcfg)["verdict"], "PASSED")


if __name__ == "__main__":
    unittest.main()
