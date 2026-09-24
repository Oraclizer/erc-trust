#!/usr/bin/env python3
"""Positive and negative controls of the tail preparation tools."""
from __future__ import annotations

import copy
import json
import shutil
import tempfile
import unittest
from pathlib import Path

import certificate_registry
import code_identity
import malformed_inputs
import prepare_tail
import route_inventory
import run_malformed_probe
import state_receipt_crosswalk
from tail_common import (
    OPERATIONS, PROFILES, PreparationError, abi_signature, keccak256, load_json, schema_errors, selector, sha256_bytes,
    sha256_file,
)


class CommonTest(unittest.TestCase):
    def test_keccak_and_selectors(self) -> None:
        self.assertEqual(keccak256(b"abc").hex(), "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45")
        self.assertEqual(selector("approve(address,uint256)"), 0x095EA7B3)
        entry = {"name": "f", "inputs": [{"type": "tuple[]", "components": [{"type": "address"}, {"type": "uint256"}]}]}
        self.assertEqual(abi_signature(entry), "f((address,uint256)[])")

    def test_schema_subset(self) -> None:
        schema = {"$defs": {"hash": {"type": "string", "pattern": "^[0-9a-f]{4}$"}}, "type": "object",
                  "required": ["a"], "additionalProperties": False,
                  "properties": {"a": {"$ref": "#/$defs/hash"}, "b": {"enum": [1, 2]},
                                 "c": {"oneOf": [{"type": "null"}, {"type": "integer", "minimum": 3}]}}}
        self.assertEqual(schema_errors({"a": "abcd", "b": 1, "c": None}, schema), [])
        self.assertTrue(schema_errors({"a": "xyz"}, schema))
        self.assertTrue(schema_errors({"a": "abcd", "d": 1}, schema))
        self.assertTrue(schema_errors({"a": "abcd", "b": 3}, schema))
        self.assertTrue(schema_errors({"a": "abcd", "c": 2}, schema))
        self.assertTrue(schema_errors({"b": 1}, schema))
        self.assertTrue(schema_errors({}, {"type": "object", "maximum": 1, "unknownKeyword": True}))


class MalformedCatalogTest(unittest.TestCase):
    def test_build_is_deterministic_and_tracked(self) -> None:
        first, table = malformed_inputs.build()
        second, _ = malformed_inputs.build()
        self.assertEqual(first, second)
        self.assertEqual(load_json(malformed_inputs.DOCUMENT), first)
        self.assertEqual(malformed_inputs.GENERATED_PROBE_TABLE.read_text(encoding="utf-8"), table)

    def test_every_guarded_word_is_probed_on_every_entrypoint(self) -> None:
        document, _ = malformed_inputs.build()
        for profile, data in document["profiles"].items():
            for entrypoint in data["typedEntrypoints"]:
                shape = document["shapes"][entrypoint["shape"]]
                guarded = {word["word"] for word in shape["words"] if word["guard"]}
                probed = {recipe["word"] for recipe in document["recipes"]
                          if recipe["profile"] == profile and recipe["entrypoint"] == entrypoint["function"]
                          and recipe["class"].startswith("dirty-")}
                self.assertEqual(guarded, probed, f"{profile} {entrypoint['function']}")

    def test_bridge_drift_is_rejected(self) -> None:
        schema = load_json(malformed_inputs.KERNEL_SCHEMA)
        abi = load_json(malformed_inputs.KERNEL_ABI)
        theory = malformed_inputs.BRIDGE_THEORY.read_text(encoding="utf-8")
        with self.assertRaisesRegex(PreparationError, "bridge length drift"):
            malformed_inputs.shape_from_sources("action", schema, abi, theory.replace(
                '"action_calldata_length = 644"', '"action_calldata_length = 643"'))
        with self.assertRaisesRegex(PreparationError, "uint48 guard drift"):
            malformed_inputs.shape_from_sources("action", schema, abi, theory.replace(
                '"action_uint48_words = [18, 19]"', '"action_uint48_words = [18]"'))
        drifted = copy.deepcopy(schema)
        drifted["structs"]["ReversalRequest"]["fields"][3]["enum"] = "ActionKind"
        with self.assertRaisesRegex(PreparationError, "enum guard drift"):
            malformed_inputs.shape_from_sources("reversal", drifted, abi, theory)


class CodeIdentityTest(unittest.TestCase):
    def test_exact_matching_rule(self) -> None:
        template = bytes(range(16))
        template = template[:4] + bytes(4) + template[8:]
        ranges = [[4, 8]]
        deployed = template[:4] + b"\x11\x22\x33\x44" + template[8:]
        self.assertTrue(code_identity.matches_template(deployed, template, ranges))
        self.assertFalse(code_identity.matches_template(deployed[:-1] + b"\xff", template, ranges))
        self.assertFalse(code_identity.matches_template(deployed + b"\x00", template, ranges))
        self.assertEqual(code_identity.merged_ranges([{"start": 4, "length": 4}, {"start": 6, "length": 4}]), [[4, 10]])

    def test_selector_loads_in_three_forms(self) -> None:
        value = 0x996B6134
        push4 = bytes([0x63]) + value.to_bytes(4, "big")
        push32 = bytes([0x7F]) + (value << 224).to_bytes(32, "big")
        shifted = bytes([0x63]) + (value >> 2).to_bytes(4, "big") + bytes([0x60, 226, 0x1B])
        hidden = bytes([0x64]) + bytes([0x63]) + value.to_bytes(4, "big")
        found = code_identity.selector_occurrences(push4 + push32 + shifted + hidden, value)
        self.assertEqual(found["push4"], [0])
        self.assertEqual(found["push32LeftAligned"], [5])
        self.assertEqual(found["shiftedPush"], [38])

    def test_tracked_document_rebuilds(self) -> None:
        document = code_identity.build_with_recorded_scan()
        self.assertEqual(load_json(code_identity.DOCUMENT), document)
        endpoints = {profile: data["endpoint"] for profile, data in document["profiles"].items()}
        scan = document["compiledScan"]["runtimes"]
        if document["compiledScan"]["status"] == "RECOMPUTED":
            for endpoint in endpoints.values():
                for name, loads in scan[endpoint]["typedFailureSelectorLoads"].items():
                    self.assertTrue(any(loads.values()), f"{endpoint} never loads {name}")


class RouteInventoryTest(unittest.TestCase):
    def test_tracked_document_rebuilds_and_is_exhaustive(self) -> None:
        document = route_inventory.build()
        self.assertEqual(load_json(route_inventory.DOCUMENT), document)
        self.assertEqual(document["counts"]["runtimes"], 7)
        for runtime in document["runtimes"]:
            self.assertEqual(len({route["selector"] for route in runtime["routes"]}), len(runtime["routes"]))

    def test_route_table_drift_is_rejected(self) -> None:
        theory = route_inventory.BRIDGE_THEORY.read_text(encoding="utf-8")
        table = route_inventory.theory_routes(theory, "native_routes")
        self.assertEqual(table[793642867], "Route_Kernel_Command")
        with self.assertRaisesRegex(PreparationError, "route table missing"):
            route_inventory.theory_routes(theory.replace("definition native_routes", "definition other_routes"),
                                          "native_routes")

    def test_dispositions(self) -> None:
        self.assertEqual(route_inventory.disposition("Route_Kernel_Command", "nonpayable"), "IN_RUNTIME_LINK_DOMAIN")
        self.assertEqual(route_inventory.disposition("Route_ERC20_View", "view"), "OUTSIDE_NON_MUTATING")
        self.assertEqual(route_inventory.disposition("Route_Governance", "nonpayable"), "OUTSIDE_REQUIRES_DISPOSITION")
        self.assertEqual(route_inventory.disposition(None, "nonpayable"), "UNCLASSIFIED")
        self.assertEqual(route_inventory.disposition(None, "pure"), "OUTSIDE_NON_MUTATING")


class CrosswalkTest(unittest.TestCase):
    def test_tracked_document_rebuilds(self) -> None:
        document = state_receipt_crosswalk.build()
        self.assertEqual(load_json(state_receipt_crosswalk.DOCUMENT), document)
        self.assertEqual(len(document["receipt"]["fields"]), 17)
        reversal = {row["input"]: row["receiptField"] for row in document["receipt"]["events"]["RegulatoryReversalApplied"]}
        self.assertEqual(reversal["actionId"], "parentCommandId")

    def test_record_parser(self) -> None:
        text = "record a =\n  first :: nat\n  second :: \"x option\"\n\nrecord b =\n  only :: bool\n"
        self.assertEqual(state_receipt_crosswalk.records(text),
                         {"a": [{"name": "first", "type": "nat"}, {"name": "second", "type": "x option"}],
                          "b": [{"name": "only", "type": "bool"}]})

    def test_projection_must_name_one_variable(self) -> None:
        layout = [{"label": "_balances", "slot": 3, "offset": 0, "type": "mapping"}]
        self.assertEqual(state_receipt_crosswalk.storage_reference(layout, "native.balances")["slot"], 3)
        with self.assertRaisesRegex(PreparationError, "no unique storage variable"):
            state_receipt_crosswalk.storage_reference(layout, "native.frozen")


class RegistryFixture:
    """A synthetic evidence root with one closed Native cell and a program record."""

    def __init__(self) -> None:
        self.root = Path(tempfile.mkdtemp(prefix="registry-test-"))
        rows = []
        for profile in PROFILES:
            for operation in OPERATIONS:
                rows.append({"id": f"cell/{profile}/{operation}", "status": "CURRENT-MANDATORY",
                             "evidence": {"sourceConsumer": [], "positiveActivation": []}})
        result = self.write("cell-root/Run01/result.json", {"status": "PASS_KERNEL_CHECKED_FIXTURE"})
        rows[0]["status"] = "CLOSED"
        rows[0]["evidence"]["positiveActivation"] = [{"kind": "kernel", "root": "cell-root", "run": "Run01",
                                                     "theory": "Fixture", "resultSha256": result}]
        self.write("ledger/obligation-ledger.json", {"rows": rows})
        self.write("certificates.json", {"applied": {"slug": "freeze-applied", "outcome": "applied", "proofId": "p1",
                                                     "proofJson": {"sha256": "a" * 64}, "kcfg": {"sha256": "b" * 64}},
                                         "rejected": {"slug": "freeze-shape-rejected", "outcome": "rejected", "proofId": "p2",
                                                      "proofJson": {"sha256": "c" * 64}, "kcfg": {"sha256": "d" * 64}}})
        fields = {"proofId": "proofId", "proofSha256": "proofJson.sha256", "kcfgSha256": "kcfg.sha256"}
        self.locators = {
            "schema": "trust12-tail-preparation-certificate-locators-v1",
            "ledger": "ledger/obligation-ledger.json",
            "cells": [{"profile": "Native", "operation": "FREEZE", "certificates": [
                {"outcome": "applied", "form": "APR_PROOF", "source": {"path": "certificates.json", "pointer": "/applied"},
                 "fields": fields},
                {"outcome": "not-applied", "form": "APR_PROOF", "source": {"path": "certificates.json", "pointer": "/rejected"},
                 "fields": fields}]}],
        }

    def write(self, relative: str, value: dict) -> str:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value), encoding="utf-8")
        return sha256_file(path)

    def close(self) -> None:
        shutil.rmtree(self.root, ignore_errors=True)


class RegistryTest(unittest.TestCase):
    def setUp(self) -> None:
        self.fixture = RegistryFixture()

    def tearDown(self) -> None:
        self.fixture.close()

    def build(self, locators: dict | None = None, mode: str = "dry-run") -> dict:
        return certificate_registry.build(self.fixture.root, locators or self.fixture.locators, None, mode)

    def check(self, registry: dict, name: str) -> str:
        return next(check["status"] for check in registry["checks"] if check["id"] == name)

    def test_dry_run_binds_the_closed_cell(self) -> None:
        registry = self.build()
        self.assertEqual(registry["status"], "DRY_RUN_PARTIAL_COVERAGE")
        self.assertEqual(registry["partition"]["boundCells"], 1)
        self.assertEqual(len(registry["partition"]["openCells"]), 26)
        self.assertEqual(self.check(registry, "cells-agree-with-ledger-and-kernels"), "PASS")

    def test_shared_kcfg_fails(self) -> None:
        document = load_json(self.fixture.root / "certificates.json")
        document["rejected"]["kcfg"]["sha256"] = "b" * 64
        self.fixture.write("certificates.json", document)
        registry = self.build()
        self.assertEqual(registry["status"], "FAIL_REGISTRY_INCONSISTENT")

    def test_duplicate_proof_fails(self) -> None:
        document = load_json(self.fixture.root / "certificates.json")
        document["rejected"]["proofId"] = "p1"
        self.fixture.write("certificates.json", document)
        self.assertEqual(self.check(self.build(), "apr-proofs-distinct"), "FAIL")

    def test_slug_naming_another_cell_fails(self) -> None:
        document = load_json(self.fixture.root / "certificates.json")
        document["applied"]["slug"] = "seize-applied"
        self.fixture.write("certificates.json", document)
        self.assertEqual(self.check(self.build(), "certificate-records-consistent"), "FAIL")

    def test_kernel_result_drift_fails(self) -> None:
        self.fixture.write("cell-root/Run01/result.json", {"status": "PASS_KERNEL_CHECKED_FIXTURE", "extra": 1})
        self.assertEqual(self.check(self.build(), "cells-agree-with-ledger-and-kernels"), "FAIL")

    def test_ledger_disagreement_fails(self) -> None:
        ledger = load_json(self.fixture.root / "ledger/obligation-ledger.json")
        ledger["rows"][0]["status"] = "CURRENT-MANDATORY"
        self.fixture.write("ledger/obligation-ledger.json", ledger)
        registry = self.build()
        self.assertEqual(self.check(registry, "cells-agree-with-ledger-and-kernels"), "FAIL")
        self.assertIn("disagrees with ledger status", " ".join(registry["checks"][3]["detail"]))

    def test_closure_mode_needs_full_coverage(self) -> None:
        with self.assertRaisesRegex(PreparationError, "closure mode needs every cell"):
            self.build(mode="closure")

    def test_locator_schema_is_enforced(self) -> None:
        locators = copy.deepcopy(self.fixture.locators)
        locators["cells"][0]["certificates"][0]["form"] = "UNKNOWN"
        with self.assertRaisesRegex(PreparationError, "locator file violates its schema"):
            self.build(locators)

    def test_registry_output_matches_its_schema(self) -> None:
        registry = self.build()
        registry["inputs"]["locators"] = None
        self.assertEqual(schema_errors(registry, load_json(certificate_registry.SCHEMA)), [])


class ObligationsTest(unittest.TestCase):
    def test_tracked_list_is_valid(self) -> None:
        self.assertEqual(prepare_tail.validate_obligations(), {"conditions": 11, "findings": 4})

    def test_unknown_finding_and_missing_artifact_fail(self) -> None:
        document = load_json(prepare_tail.OBLIGATIONS)
        broken = copy.deepcopy(document)
        broken["conditions"][0]["blockingFindings"] = ["no-such-finding"]
        with self.assertRaisesRegex(PreparationError, "unknown finding"):
            prepare_tail.validate_obligations(broken)
        broken = copy.deepcopy(document)
        broken["conditions"][0]["preparedSupport"][0]["artifact"] = "README.md"
        with self.assertRaisesRegex(PreparationError, "not a prepared artifact"):
            prepare_tail.validate_obligations(broken)
        broken = copy.deepcopy(document)
        broken["status"] = "CLOSED"
        with self.assertRaisesRegex(PreparationError, "more than preparation"):
            prepare_tail.validate_obligations(broken)


class ProbeEvaluationTest(unittest.TestCase):
    quiet = {"externalAccesses": 0, "logs": 0, "committedWrites": 0, "secondWord": 0, "returnBytes": 0}

    def test_verdicts(self) -> None:
        evaluate = run_malformed_probe.evaluate
        empty = {**self.quiet, "outcome": "untyped-empty-revert", "selector": None}
        typed = {**self.quiet, "outcome": "typed-failure", "selector": "0xed623c13", "secondWord": 1, "returnBytes": 68}
        self.assertEqual(evaluate({"class": "length"}, empty)["verdict"], "CONFORMS")
        self.assertEqual(evaluate({"class": "length"}, {**empty, "externalAccesses": 1})["verdict"], "DEVIATES")
        self.assertEqual(evaluate({"class": "length"}, {**empty, "logs": 1})["verdict"], "DEVIATES")
        self.assertEqual(evaluate({"class": "length"}, {**empty, "committedWrites": 1})["verdict"], "DEVIATES")
        self.assertEqual(evaluate({"class": "dirty-address-word"}, typed)["verdict"], "CONFORMS")
        self.assertEqual(evaluate({"class": "nonzero-call-value"}, empty)["verdict"], "CONFORMS")
        self.assertEqual(evaluate({"class": "dirty-enum-word"}, {**empty, "outcome": "success"})["verdict"], "DEVIATES")
        self.assertEqual(evaluate({"class": "unlisted"}, empty)["verdict"], "UNKNOWN_CLASS")
        verdict = evaluate({"class": "ordering-probe"}, typed)
        self.assertEqual((verdict["verdict"], verdict["typedFailure"], verdict["reason"]),
                         ("CONFORMS", "TrustInvalidCommand", 1))
        control = {"outcome": "success", "selector": None, "secondWord": 0, "returnBytes": 32,
                   "externalAccesses": 3, "logs": 2, "committedWrites": 5}
        self.assertEqual(evaluate({"class": "well-formed-control"}, control)["verdict"], "CONTROL_DETECTED")
        self.assertEqual(evaluate({"class": "well-formed-control"}, {**control, "logs": 0})["verdict"], "CONTROL_FAILED")
        self.assertEqual(evaluate({"class": "length"}, None)["verdict"], "NOT_OBSERVED")

    def test_event_decoding(self) -> None:
        topic = run_malformed_probe.topic(run_malformed_probe.RESULT_EVENT)
        words = [2, 0, 1, 68, 0, 0, 0]
        data = b"".join(value.to_bytes(32, "big") for value in words)
        data = data[:32] + bytes.fromhex("ed623c13") + bytes(28) + data[64:]
        report = {"suite.sol:Probe": {"test_results": {"testProbe()": {"status": "Success", "logs": [
            {"address": "0x0", "topics": [topic, "0x" + (7).to_bytes(32, "big").hex()], "data": "0x" + data.hex()}]}}}}
        results, bases, statuses = run_malformed_probe.decode_results(report)
        self.assertEqual(statuses, {"Probe.testProbe()": "Success"})
        self.assertEqual(results[7]["outcome"], "typed-failure")
        self.assertEqual(results[7]["selector"], "0xed623c13")
        self.assertEqual(results[7]["secondWord"], 1)
        self.assertEqual(bases, [])


class GeneratedDocumentsTest(unittest.TestCase):
    def test_every_generated_document_is_current(self) -> None:
        result = prepare_tail.generate(check=True, artifacts=None)
        self.assertEqual(result["obligations"], {"conditions": 11, "findings": 4})
        for name, digest in result.items():
            if name != "obligations":
                self.assertRegex(digest, "^[0-9a-f]{64}$")

    def test_no_private_coordinate_in_prepared_outputs(self) -> None:
        # The patterns are assembled at run time so that this file does not itself contain one.
        drive = "[A-Za-z]:[/\\\\]" + "Users" + "[/\\\\]"
        home = "/" + "home" + "/[a-z_]+/"
        for prefix in prepare_tail.PRODUCT_PREFIXES:
            for path in (prepare_tail.ROOT / prefix).rglob("*"):
                if path.is_file() and path.suffix in {".json", ".md", ".py", ".sol"}:
                    text = path.read_text(encoding="utf-8")
                    self.assertNotRegex(text, drive, str(path))
                    self.assertNotRegex(text, home, str(path))
                    self.assertNotIn(chr(0x2014), text, str(path))
                    self.assertEqual(sha256_bytes(path.read_bytes()), sha256_file(path))


if __name__ == "__main__":
    unittest.main()
