#!/usr/bin/env python3
"""Checks of the reflection scan that need no build, and of the tracked reflection dispositions."""
from __future__ import annotations

import copy
import unittest

import reflection_scan as scan
from tail_common import ROOT, load_json


def crosswalk(open_items=("first open item",)):
    return {
        "stateFields": [
            {"abstract": "a", "runtimes": {
                "TrustToken": {"status": "BOUND_BY_CENTRAL_LEDGER",
                               "storage": {"label": "_x", "slot": 0, "offset": 0, "type": "uint256"}},
                "ERC3643TrustAdapter": {"status": "BOUND_BY_CENTRAL_LEDGER",
                                        "storage": {"label": "_b", "slot": 2, "offset": 0, "type": "bool"}},
                "ERC3643HookAdapter": {"status": scan.DERIVED,
                                       "storage": {"label": "_b", "slot": 2, "offset": 0, "type": "bool"}}}},
        ],
        "storageWithoutAbstractField": {"TrustToken": [
            {"label": "_p", "slot": 5, "offset": 0, "type": "mapping(bytes32 => uint256)", "status": scan.OPEN,
             "reflection": None}]},
        "openItems": list(open_items),
    }


def layout(*items):
    types = {f"t_{label}": {"label": kind} for label, _, kind in items}
    return {"storage": [{"label": label, "slot": str(slot), "offset": 0, "type": f"t_{label}"}
                        for label, slot, _ in items], "types": types}


class HelperTest(unittest.TestCase):
    def test_snippet_core_drops_block_punctuation(self):
        self.assertEqual(scan.snippet_core("} else if (a != b) {"), "if (a != b)")
        self.assertEqual(scan.snippet_core("revert X();"), "revert X()")

    def test_review_pending_counts_the_draft_status_and_review_notes(self):
        self.assertEqual(scan.review_pending({"status": scan.REVIEWED}), 0)
        self.assertEqual(scan.review_pending({"status": "DRAFT_FOR_REVIEW", "guards": [{"review": "check"}, {}]}), 2)


class LayoutTest(unittest.TestCase):
    LAYOUTS = {"TrustToken": layout(("_x", 0, "uint256"), ("_p", 5, "mapping(bytes32 => uint256)")),
               "ERC3643TrustAdapter": layout(("_b", 2, "bool")), "ERC3643HookAdapter": layout(("_b", 2, "bool"))}
    DECLARED = {"TrustToken": {"_x", "_p"}, "ERC3643TrustAdapter": {"_b"}, "ERC3643HookAdapter": {"_b"}}

    def problems(self, layouts=None, declared=None):
        return scan.layout_problems(crosswalk(), layouts or self.LAYOUTS, declared or self.DECLARED)[0]

    def test_matching_layouts_pass(self):
        self.assertEqual(self.problems(), [])

    def test_a_moved_slot_is_reported(self):
        layouts = copy.deepcopy(self.LAYOUTS)
        layouts["TrustToken"]["storage"][1]["slot"] = "6"
        self.assertTrue(any("_p" in item for item in self.problems(layouts)))

    def test_a_variable_outside_the_crosswalk_is_reported(self):
        layouts = copy.deepcopy(self.LAYOUTS)
        layouts["TrustToken"] = layout(("_x", 0, "uint256"), ("_p", 5, "mapping(bytes32 => uint256)"), ("_n", 7, "bool"))
        declared = {**self.DECLARED, "TrustToken": {"_x", "_p", "_n"}}
        self.assertTrue(any("_n" in item for item in self.problems(layouts, declared)))

    def test_a_runtime_with_state_needs_a_layout(self):
        layouts = {**self.LAYOUTS, "TrustToken": None}
        self.assertTrue(any(item.startswith("TrustToken") for item in self.problems(layouts)))

    def test_declared_and_compiled_variables_must_agree(self):
        declared = {**self.DECLARED, "TrustToken": {"_x"}}
        self.assertTrue(any("declared" in item for item in self.problems(declared=declared)))


class DispositionTest(unittest.TestCase):
    SITES = {"TrustToken": [{"variable": "_p", "function": "f", "kind": "assignment", "text": "_p[k] = v"},
                            {"variable": "_p", "function": "g", "kind": "delete", "text": "delete _p[k]"}]}
    ROWS = {"central": {"R-1"}, "trust12": {"P-1"}}
    DISPOSITIONS = {
        "storage": [{"runtime": "TrustToken", "label": "_p", "slot": 5, "reason": "carrier", "assignedBy": ["f"],
                     "clearedBy": ["g"], "rows": ["R-1"], "ledger": "central"}],
        "guards": [{"runtime": "TrustToken", "function": "h", "statement": "if (x) revert Y()", "rows": ["P-1"],
                    "ledger": "trust12"}],
        "openItems": [{"index": 0, "text": "first open item", "disposition": "ASSUMPTION", "detail": "d",
                       "assumption": "A-K"}],
    }
    USED = {("TrustToken", "h", "if (x) revert Y()")}

    def problems(self, dispositions=None, used=None, sites=None, hook=()):
        return scan.disposition_problems(crosswalk(), dispositions or self.DISPOSITIONS, self.ROWS, {"A-K"},
                                         sites or self.SITES, self.USED if used is None else used, list(hook))

    def changed(self, edit):
        dispositions = copy.deepcopy(self.DISPOSITIONS)
        edit(dispositions)
        return self.problems(dispositions)

    def test_complete_dispositions_pass(self):
        self.assertEqual(self.problems(), [])

    def test_storage_writers_must_be_exact(self):
        self.assertTrue(self.changed(lambda d: d["storage"][0].__setitem__("clearedBy", [])))
        self.assertTrue(self.changed(lambda d: d["storage"][0].__setitem__("assignedBy", ["f", "k"])))

    def test_storage_write_kinds_must_match(self):
        self.assertTrue(self.changed(lambda d: d["storage"][0].update(assignedBy=["g"], clearedBy=["f"])))

    def test_open_storage_needs_a_disposition_and_the_slot(self):
        self.assertTrue(self.changed(lambda d: d.__setitem__("storage", [])))
        self.assertTrue(self.changed(lambda d: d["storage"][0].__setitem__("slot", 6)))

    def test_rows_and_assumptions_must_exist(self):
        self.assertTrue(self.changed(lambda d: d["storage"][0].__setitem__("rows", ["R-9"])))
        self.assertTrue(self.changed(lambda d: d["guards"][0].__setitem__("ledger", "central")))
        self.assertTrue(self.changed(lambda d: d["openItems"][0].__setitem__("assumption", "A-Z")))

    def test_a_guard_disposition_must_match_a_scanned_guard(self):
        self.assertTrue(self.problems(used=set()))

    def test_open_items_quote_the_crosswalk_and_carry_with_four_fields(self):
        self.assertTrue(self.changed(lambda d: d["openItems"][0].__setitem__("text", "another text")))
        carried = {"receivingGate": "g", "owner": "o", "closureEvidence": "e", "reopen": "r"}
        self.assertEqual(self.changed(lambda d: d["openItems"][0].update(disposition="NEEDS_DECISION",
                                                                          carryOver=carried)), [])
        for name in scan.CARRY_FIELDS:
            partial = {key: value for key, value in carried.items() if key != name}
            self.assertTrue(self.changed(lambda d: d["openItems"][0].update(disposition="NEEDS_DECISION",
                                                                             carryOver=partial)), name)

    def test_resolved_by_scan_needs_a_clean_hook_review(self):
        resolved = copy.deepcopy(self.DISPOSITIONS)
        resolved["openItems"][0].update(disposition="RESOLVED_BY_SCAN")
        self.assertEqual(self.problems(resolved), [])
        self.assertTrue(self.problems(resolved, hook=["Hook problem"]))


class HookReviewTest(unittest.TestCase):
    SITES = {"ERC3643HookAdapter": [{"variable": "_b", "function": "w"}],
             "ERC3643TrustAdapter": [{"variable": "_b", "function": "w"}]}
    TEXTS = {("ERC3643HookAdapter", "w"): "function w() { _b = hook(); }",
             ("ERC3643TrustAdapter", "w"): "function w() { _b = partial(); }"}

    def item(self):
        return {"runtime": "ERC3643HookAdapter", "function": "w", "labels": ["_b"],
                "textSha256": scan.sha256_text(self.TEXTS[("ERC3643HookAdapter", "w")]), "partialFunction": "w",
                "partialTextSha256": scan.sha256_text(self.TEXTS[("ERC3643TrustAdapter", "w")]),
                "difference": "reads hook()", "reason": "same field"}

    def review(self, writers, texts=None):
        texts = texts or self.TEXTS
        return scan.hook_review(crosswalk(), self.SITES, {"hookColumnWriters": writers},
                                lambda runtime, function: texts.get((runtime, function)))

    def test_identical_writers_need_no_disposition(self):
        same = {**self.TEXTS, ("ERC3643HookAdapter", "w"): self.TEXTS[("ERC3643TrustAdapter", "w")]}
        columns, problems = self.review([], same)
        self.assertEqual(problems, [])
        self.assertEqual(columns[0]["writersWithOwnText"], [])

    def test_a_writer_with_its_own_text_needs_a_pinned_disposition(self):
        self.assertTrue(self.review([])[1])
        self.assertEqual(self.review([self.item()])[1], [])

    def test_a_changed_text_reopens_the_review(self):
        texts = {**self.TEXTS, ("ERC3643HookAdapter", "w"): "function w() { _b = other(); }"}
        self.assertTrue(self.review([self.item()], texts)[1])
        texts = {**self.TEXTS, ("ERC3643TrustAdapter", "w"): "function w() { _b = other(); }"}
        self.assertTrue(self.review([self.item()], texts)[1])

    def test_a_disposition_without_a_matching_writer_is_reported(self):
        same = {**self.TEXTS, ("ERC3643HookAdapter", "w"): self.TEXTS[("ERC3643TrustAdapter", "w")]}
        self.assertTrue(self.review([self.item()], same)[1])


class TrackedDispositionsTest(unittest.TestCase):
    """The tracked dispositions agree with the tracked crosswalk and name existing rows; the build checks the rest."""

    def setUp(self):
        self.dispositions = load_json(ROOT / scan.DISPOSITIONS)
        self.crosswalk = load_json(ROOT / scan.CROSSWALK)
        central, profile = (load_json(ROOT / scan.LEDGERS[name]) for name in ("central", "trust12"))
        self.rows = {"central": {row["id"] for row in central["rows"]},
                     "trust12": {row["id"] for row in profile["obligations"]}}
        self.assumptions = {item["id"] for item in central["assumptions"]}

    def test_storage_dispositions_cover_exactly_the_open_storage(self):
        open_rows = {(name, row["label"]): row["slot"] for name, items in self.crosswalk["storageWithoutAbstractField"]
                     .items() for row in items if row["status"] == scan.OPEN}
        disposed = {(item["runtime"], item["label"]): item["slot"] for item in self.dispositions["storage"]}
        self.assertEqual(disposed, open_rows)

    def test_open_item_dispositions_quote_the_crosswalk(self):
        self.assertEqual([item["text"] for item in sorted(self.dispositions["openItems"], key=lambda x: x["index"])],
                         self.crosswalk["openItems"])

    def test_named_rows_and_assumptions_exist(self):
        for section in ("storage", "guards", "hookColumnWriters"):
            for item in self.dispositions[section]:
                self.assertEqual(scan.row_problems(item, self.rows, section), [])
        for item in self.dispositions["openItems"]:
            if item["disposition"] == "ASSUMPTION":
                self.assertIn(item["assumption"], self.assumptions)


if __name__ == "__main__":
    unittest.main()
