#!/usr/bin/env python3
"""Positive and negative controls of the version 2 route inventory and the route disposition test runner.

The controls read the tracked product files only and use synthetic run records; no Foundry run and no private
file is involved.
"""
from __future__ import annotations

import copy
import json
import shutil
import tempfile
import unittest
from pathlib import Path

import route_inventory_v2
import run_route_disposition_tests
from tail_common import ROOT, PreparationError, load_json, sha256_file

DECISION = ROOT / "spec/decisions/14-hook-route-classes.md"
CLASSES = ROOT / "spec/generated/hook-route-classes-v1.json"
DISPOSITIONS = ROOT / "evidence/trust12/runtime-link/tail-preparation/route-dispositions-v1.json"
HOOK_SEAL = "ERC3643HookAdapter.activateSeal((address,uint256,bool)[])"
APPROVE = "TrustToken.approve(address,uint256)"
PARTIAL_RESYNC = "ERC3643TrustAdapter.resynchroniseFrozen(address)"


def synthetic_probe() -> dict:
    """Rows in the form of the malformed probe receipt for the catalogued unknown-selector requests."""
    catalog = load_json(route_inventory_v2.v1.MALFORMED)
    rows = [{"id": item["id"], "profile": item["profile"], "class": "unknown-selector", "verdict": "CONFORMS",
             "observed": {"outcome": "untyped-empty-revert", "returnBytes": 0, "logs": 0, "committedWrites": 0,
                          "externalAccesses": 0}}
            for item in catalog["recipes"] if item["class"] == "unknown-selector"]
    summary = load_json(route_inventory_v2.PROBE_SUMMARY)
    return {"sha256": summary["malformedInput"]["receiptSha256"], "status": "PROBE_RECORDED", "rows": rows}


def synthetic_run() -> dict:
    """A run record in which every declared route test passed on the current test files."""
    tests = [{"suite": suite, "test": test, "status": "Success"}
             for suite, test in run_route_disposition_tests.declared_tests(ROOT)]
    sources = {f"{route_inventory_v2.ROUTE_TESTS}/{path.name}": sha256_file(path)
               for path in sorted((ROOT / route_inventory_v2.ROUTE_TESTS).glob("*.sol"))}
    return {"sha256": "0" * 64, "status": route_inventory_v2.RUN_PASSED, "forgeVersion": "synthetic",
            "implementationRootSha256": run_route_disposition_tests.implementation_root(ROOT), "sources": sources,
            "tests": tests}


class Workspace:
    """Temporary copies of the class record and the disposition records that a test may edit."""

    def __init__(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.decision = self.root / DECISION.name
        self.classes = self.root / CLASSES.name
        self.dispositions = self.root / DISPOSITIONS.name
        shutil.copyfile(DECISION, self.decision)
        shutil.copyfile(DISPOSITIONS, self.dispositions)
        self.render()

    def render(self) -> None:
        self.classes.write_text(json.dumps(route_inventory_v2.render_classes(self.decision), indent=2) + "\n",
                                encoding="utf-8")

    def edit_decision(self, old: str, new: str) -> None:
        text = self.decision.read_text(encoding="utf-8")
        assert text.count(old) == 1, old
        self.decision.write_text(text.replace(old, new), encoding="utf-8")

    def edit_dispositions(self, change) -> None:
        document = load_json(self.dispositions)
        change(document)
        self.dispositions.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")

    def build(self, mode: str = "prepare", probe: dict | None = None, run: dict | None = None):
        return route_inventory_v2.build(mode, self.decision, self.classes, self.dispositions, probe, run)

    def close(self) -> None:
        self.directory.cleanup()


def failed(document: dict) -> set[str]:
    return {item["id"] for item in document["closure"]["criteria"] if not item["holds"]}


def record(document: dict, route: str) -> dict:
    return next(item for item in document["dispositionRecords"] if item["route"] == route)


class RouteInventoryV2Test(unittest.TestCase):
    def setUp(self) -> None:
        self.work = Workspace()

    def tearDown(self) -> None:
        self.work.close()

    def test_generated_table_is_the_rendering_of_the_decision(self) -> None:
        rendered = route_inventory_v2.render_classes(DECISION)
        self.assertEqual(load_json(CLASSES), rendered)
        self.assertEqual(rendered["status"], "NORMATIVE")

    def test_prepare_mode_classifies_every_selector(self) -> None:
        document = self.work.build()
        self.assertEqual(document["counts"]["runtimes"], 7)
        self.assertEqual(document["counts"]["selectors"], 108)
        self.assertEqual(document["counts"]["unclassifiedStateChanging"], 0)
        self.assertEqual(document["counts"]["stateChangingOutsideTheTypedCommands"], 20)
        hook = next(runtime for runtime in document["runtimes"] if runtime["contract"] == "ERC3643HookAdapter")
        domain = sorted(route["selector"] for route in hook["routes"] if route["disposition"] == "IN_RUNTIME_LINK_DOMAIN")
        self.assertEqual(domain, ["0x2b892e8f", "0x2f4e0773"])
        self.assertEqual(document["status"], "PREPARED_NOT_CLOSED")

    def test_closure_with_both_runs_closes(self) -> None:
        document = self.work.build("closure", synthetic_probe(), synthetic_run())
        self.assertEqual(failed(document), set())
        self.assertEqual(document["status"], "CLOSED_ROUTE_INVENTORY")
        self.assertEqual(document["counts"]["dispositionsComplete"], 20)
        self.assertEqual(document["unmatchedSelectors"]["dispatcherSelector"], "0xffffffff")

    def test_closure_fails_without_the_runs(self) -> None:
        document = self.work.build("closure")
        self.assertEqual(failed(document), {"every-state-changing-route-outside-the-typed-commands-is-disposed",
                                            "unknown-selectors-revert-empty-on-every-endpoint"})
        self.assertIn("the disposition test run is not supplied", record(document, HOOK_SEAL)["gaps"])

    def test_accepted_status_of_the_class_record_is_required(self) -> None:
        self.work.edit_decision("Status: accepted.", "Status: proposed.")
        self.work.render()
        document = self.work.build("closure", synthetic_probe(), synthetic_run())
        self.assertEqual(failed(document), {"hook-class-record-accepted"})

    def test_a_proposed_disposition_decision_does_not_justify(self) -> None:
        original = route_inventory_v2.accepted
        route_inventory_v2.accepted = lambda line: not line.startswith("accepted. It states")
        try:
            document = self.work.build("closure", synthetic_probe(), synthetic_run())
        finally:
            route_inventory_v2.accepted = original
        self.assertFalse(record(document, APPROVE)["justified"])
        self.assertFalse(record(document, HOOK_SEAL)["justified"])
        self.assertIn("every-state-changing-route-outside-the-typed-commands-is-disposed", failed(document))

    def test_the_class_record_cannot_justify(self) -> None:
        def change(document):
            item = next(row for row in document["dispositions"] if row["route"] == APPROVE)
            item["references"].append({"type": "decision", "path": "spec/decisions/14-hook-route-classes.md",
                                       "quote": "Route_Kernel_Command", "coverage": "this runtime"})
        self.work.edit_dispositions(change)
        with self.assertRaisesRegex(PreparationError, "the class record cannot justify"):
            self.work.build()

    def test_failed_route_test_leaves_every_run_reference_open(self) -> None:
        run = synthetic_run()
        run["tests"][0]["status"] = "Failure"
        document = self.work.build("closure", synthetic_probe(), run)
        self.assertFalse(record(document, HOOK_SEAL)["complete"])
        self.assertIn("the disposition test run did not pass every declared route test", record(document, HOOK_SEAL)["gaps"])

    def test_run_without_a_declared_test_is_rejected(self) -> None:
        run = synthetic_run()
        run["tests"] = run["tests"][1:]
        document = self.work.build("closure", synthetic_probe(), run)
        self.assertIn("every-state-changing-route-outside-the-typed-commands-is-disposed", failed(document))

    def test_run_of_other_bytes_is_not_an_execution(self) -> None:
        run = synthetic_run()
        hook_file = next(path for path in run["sources"] if path.endswith("HookRouteDispositions.t.sol"))
        run["sources"][hook_file] = "0" * 64
        document = self.work.build("closure", synthetic_probe(), run)
        self.assertFalse(record(document, HOOK_SEAL)["executedOnThisRuntime"])
        self.assertTrue(record(document, APPROVE)["executedOnThisRuntime"])

    def test_run_of_other_implementation_sources_is_not_an_execution(self) -> None:
        run = synthetic_run()
        run["implementationRootSha256"] = "0" * 64
        document = self.work.build("closure", synthetic_probe(), run)
        self.assertFalse(record(document, APPROVE)["executedOnThisRuntime"])
        self.assertIn("the disposition test run did not compile the current implementation sources and tests",
                      record(document, HOOK_SEAL)["gaps"])
        self.assertIn("every-state-changing-route-outside-the-typed-commands-is-disposed", failed(document))

    def test_recorded_suite_must_bind_the_current_sources(self) -> None:
        original = route_inventory_v2.implementation_root
        route_inventory_v2.implementation_root = lambda: "0" * 64
        try:
            document = self.work.build("closure", synthetic_probe(), synthetic_run())
        finally:
            route_inventory_v2.implementation_root = original
        self.assertFalse(record(document, PARTIAL_RESYNC)["executedOnThisRuntime"])
        self.assertIn("the recorded Foundry results do not bind the current implementation sources and tests",
                      record(document, PARTIAL_RESYNC)["gaps"])

    def test_recorded_suite_test_must_be_recorded_as_passed(self) -> None:
        def change(document):
            item = next(row for row in document["dispositions"] if row["route"] == "TrustToken.transfer(address,uint256)")
            item["references"] = [ref for ref in item["references"] if ref["type"] != "test"] + [
                {"type": "test", "runtime": "TrustToken", "run": "recorded-foundry-suite",
                 "suite": "implementation/test/TrustStateful.invariant.t.sol:TrustStatefulInvariantTest",
                 "test": "invariantSupplyConserved"}]
        self.work.edit_dispositions(change)
        document = self.work.build("closure", synthetic_probe(), synthetic_run())
        self.assertTrue(record(document, "TrustToken.transfer(address,uint256)")["executedOnThisRuntime"])

        def handler(document):
            item = next(row for row in document["dispositions"] if row["route"] == "TrustToken.transfer(address,uint256)")
            item["references"] = [ref for ref in item["references"] if ref["type"] != "test"] + [
                {"type": "test", "runtime": "TrustToken", "run": "recorded-foundry-suite",
                 "suite": "implementation/test/TrustStateful.invariant.t.sol:TrustRegulatoryHandler",
                 "test": "transferBounded"}]
        self.work.edit_dispositions(handler)
        document = self.work.build("closure", synthetic_probe(), synthetic_run())
        self.assertFalse(record(document, "TrustToken.transfer(address,uint256)")["executedOnThisRuntime"])

    def test_test_reference_shape_is_enforced(self) -> None:
        def extra(document):
            next(row for row in document["dispositions"] if row["route"] == APPROVE)["references"][-1]["function"] = "x"
        self.work.edit_dispositions(extra)
        with self.assertRaisesRegex(PreparationError, "test reference fields differ"):
            self.work.build()

    def test_test_reference_of_the_wrong_run_directory_fails(self) -> None:
        def moved(document):
            next(row for row in document["dispositions"] if row["route"] == APPROVE)["references"][-1]["run"] = \
                "recorded-foundry-suite"
        self.work.edit_dispositions(moved)
        with self.assertRaisesRegex(PreparationError, "is not a test file of the recorded-foundry-suite"):
            self.work.build()

    def test_probe_receipt_must_be_the_bound_receipt(self) -> None:
        probe = synthetic_probe()
        probe["sha256"] = "0" * 64
        with self.assertRaisesRegex(PreparationError, "is not the receipt the tracked probe summary binds"):
            self.work.build("closure", probe, synthetic_run())

    def test_probe_row_with_revert_data_fails(self) -> None:
        probe = synthetic_probe()
        probe["rows"][0]["observed"]["returnBytes"] = 4
        document = self.work.build("closure", probe, synthetic_run())
        self.assertEqual(failed(document), {"unknown-selectors-revert-empty-on-every-endpoint"})

    def test_probe_rows_must_be_the_catalogued_requests(self) -> None:
        probe = synthetic_probe()
        probe["rows"] = probe["rows"][1:]
        document = self.work.build("closure", probe, synthetic_run())
        self.assertEqual(failed(document), {"unknown-selectors-revert-empty-on-every-endpoint"})

    def test_catalogued_request_must_be_the_dispatcher_selector_with_a_freeze_body(self) -> None:
        catalog = load_json(route_inventory_v2.v1.MALFORMED)
        runtimes = [{"routes": [{"selector": "0x095ea7b3"}]}]
        result = route_inventory_v2.unknown_selector_evidence(synthetic_probe(), catalog, 0xFFFFFFFF, runtimes,
                                                              route_inventory_v2.Reads())
        self.assertEqual(result["status"], "VERIFIED")
        for field, value in (("value", "0xfffffffe"), ("base", "ACTION-UNFREEZE"), ("calldataBytes", 645)):
            changed = copy.deepcopy(catalog)
            next(item for item in changed["recipes"] if item["class"] == "unknown-selector")[field] = value
            result = route_inventory_v2.unknown_selector_evidence(synthetic_probe(), changed, 0xFFFFFFFF, runtimes,
                                                                  route_inventory_v2.Reads())
            self.assertEqual(result["status"], "FAILED", field)

    def test_probe_inputs_must_be_the_current_files(self) -> None:
        original = route_inventory_v2.tab_root
        route_inventory_v2.tab_root = lambda paths: "0" * 64
        try:
            document = self.work.build("closure", synthetic_probe(), synthetic_run())
        finally:
            route_inventory_v2.tab_root = original
        self.assertEqual(failed(document), {"unknown-selectors-revert-empty-on-every-endpoint"})

    def test_class_outside_the_vocabulary_fails(self) -> None:
        self.work.edit_decision("| `0x39c6db74` | `Route_Unit_Creation` |", "| `0x39c6db74` | `Route_Made_Up` |")
        with self.assertRaisesRegex(PreparationError, "class outside the vocabulary"):
            self.work.render()

    def test_selector_that_does_not_match_its_signature_fails(self) -> None:
        self.work.edit_decision("| `sealFresh()` | `0xa941f8f9` |", "| `sealFresh()` | `0xa941f8f8` |")
        with self.assertRaisesRegex(PreparationError, "selector does not match"):
            self.work.render()

    def test_spec_class_may_not_shadow_a_formal_class(self) -> None:
        self.work.edit_decision("| `Route_Unit_Creation` | yes |", "| `Route_Seal_Command` | yes |")
        with self.assertRaisesRegex(PreparationError, "shadows a formal class"):
            self.work.render()

    def test_missing_hook_row_fails(self) -> None:
        self.work.edit_decision("| `ERC3643HookGovernor` | `sealFresh()` | `0xa941f8f9` | `Route_Seal_Command` |\n", "")
        self.work.render()
        with self.assertRaisesRegex(PreparationError, "compiled selectors and the Hook class table differ"):
            self.work.build()

    def test_class_must_agree_with_abi_mutability(self) -> None:
        self.work.edit_decision("| `sealFresh()` | `0xa941f8f9` | `Route_Seal_Command` |",
                                "| `sealFresh()` | `0xa941f8f9` | `Route_Seal_View` |")
        self.work.render()
        with self.assertRaisesRegex(PreparationError, "disagrees with ABI mutability"):
            self.work.build()

    def test_class_must_agree_with_the_counterpart(self) -> None:
        self.work.edit_decision("| `resynchroniseFrozen(address)` | `0x24933056` | `Route_Profile_Command` |",
                                "| `resynchroniseFrozen(address)` | `0x24933056` | `Route_Governance` |")
        self.work.render()
        with self.assertRaisesRegex(PreparationError, "differs from the counterpart class"):
            self.work.build()

    def test_wrong_occurrence_count_fails(self) -> None:
        def change(document):
            item = next(row for row in document["dispositions"] if row["route"].startswith("ERC3643HookFactory."))
            next(ref for ref in item["references"] if ref["type"] == "source")["occurrences"] = 2
        self.work.edit_dispositions(change)
        with self.assertRaisesRegex(PreparationError, "occurrences of a cited line"):
            self.work.build()

    def test_record_for_a_view_route_fails(self) -> None:
        def change(document):
            item = copy.deepcopy(document["dispositions"][-1])
            item["route"], item["selector"] = "ERC3643HookFactory.tokenCreationSource()", "0xaf897f60"
            document["dispositions"].append(item)
        self.work.edit_dispositions(change)
        with self.assertRaisesRegex(PreparationError, "names no state-changing route"):
            self.work.build()

    def test_ledger_row_of_another_runtime_fails(self) -> None:
        def change(document):
            item = next(row for row in document["dispositions"] if row["route"].startswith("ERC3643HookFactory."))
            item["references"].append({"type": "ledgerRow", "ledger": "evidence/end-to-end-refinement/obligation-ledger-v3.json",
                                       "row": "NAT-XFER-01", "coverage": "this runtime"})
        self.work.edit_dispositions(change)
        with self.assertRaisesRegex(PreparationError, "is not about this runtime"):
            self.work.build()

    def test_missing_record_leaves_the_route_undisposed(self) -> None:
        self.work.edit_dispositions(lambda document: document["dispositions"].pop())
        document = self.work.build("closure", synthetic_probe(), synthetic_run())
        factory = next(runtime for runtime in document["runtimes"] if runtime["contract"] == "ERC3643HookFactory")
        deploy = next(route for route in factory["routes"] if route["selector"] == "0x39c6db74")
        self.assertEqual(deploy["disposition"], "OUTSIDE_REQUIRES_DISPOSITION")
        self.assertIn("every-state-changing-route-outside-the-typed-commands-is-disposed", failed(document))

    def test_recorded_gap_keeps_the_record_open(self) -> None:
        def change(document):
            next(row for row in document["dispositions"] if row["route"] == APPROVE)["gaps"] = ["open question"]
        self.work.edit_dispositions(change)
        document = self.work.build("closure", synthetic_probe(), synthetic_run())
        self.assertFalse(record(document, APPROVE)["complete"])

    def test_inputs_name_every_file_the_build_read(self) -> None:
        document = self.work.build("closure", synthetic_probe(), synthetic_run())
        paths = {item["path"] for item in document["inputs"]}
        for required in ("spec/decisions/15-route-dispositions.md", "evidence/foundry-results-v3.json",
                         "evidence/trust12/runtime-link/out-of-spec-probes-v1.json",
                         "scripts/trust12/tail-preparation/route-dispositions/HookRouteDispositions.t.sol"):
            self.assertIn(required, paths)
        self.assertNotIn("evidence/trust12/obligation-ledger.json", paths)


class RouteDispositionRunnerTest(unittest.TestCase):
    def report(self) -> dict:
        report: dict = {}
        for suite, test in run_route_disposition_tests.declared_tests(ROOT):
            report.setdefault(suite, {"test_results": {}})["test_results"][test] = {"status": "Success"}
        return report

    def run_record(self, report: dict, exit_code: int = 0) -> dict:
        return run_route_disposition_tests.record(report, {"command": "synthetic", "exitCode": exit_code}, "0" * 64,
                                                  ROOT, "synthetic")

    def test_every_declared_test_passed(self) -> None:
        receipt = self.run_record(self.report())
        self.assertEqual(receipt["status"], run_route_disposition_tests.PASSED)
        self.assertEqual(receipt["declaredTests"], len(receipt["tests"]))

    def test_receipt_records_the_source_root_of_the_recorded_foundry_results(self) -> None:
        receipt = self.run_record(self.report())
        self.assertEqual(receipt["implementationRootSha256"], route_inventory_v2.implementation_root())

    def test_failure_missing_test_or_exit_code_fails(self) -> None:
        report = self.report()
        suite = next(iter(report))
        test = next(iter(report[suite]["test_results"]))
        report[suite]["test_results"][test]["status"] = "Failure"
        self.assertNotEqual(self.run_record(report)["status"], run_route_disposition_tests.PASSED)
        report = self.report()
        report[suite]["test_results"].pop(test)
        self.assertNotEqual(self.run_record(report)["status"], run_route_disposition_tests.PASSED)
        self.assertNotEqual(self.run_record(self.report(), 1)["status"], run_route_disposition_tests.PASSED)


if __name__ == "__main__":
    unittest.main()
