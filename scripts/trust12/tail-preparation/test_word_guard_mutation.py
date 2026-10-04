#!/usr/bin/env python3
"""Unit tests of the bounded word guard mutants: synthetic sources and the current product sources."""
from __future__ import annotations

import copy
import json
import re
import unittest
from pathlib import Path

import word_guard_mutation as mutation
from run_word_guard_probe import ENTRYPOINTS, KIND_CONTROL_WORD, WITNESS_BASE, expectation, witness_table

ROOT = Path(__file__).resolve().parents[3]
CATALOG = json.loads((ROOT / "evidence/trust12/runtime-link/tail-preparation/malformed-inputs-v1.json").read_text(
    encoding="utf-8"))
MUTANTS = json.loads((ROOT / "evidence/trust12/runtime-link/tail-preparation/malformed-word-guard-mutants-v1.json")
                     .read_text(encoding="utf-8"))

SYNTHETIC = """contract Endpoint {
    // request.subject in a comment stays
    string internal constant NOTE = "request.subject in a string stays";

    function executeRegulatoryAction(TrustKernelTypes.ActionRequest calldata request) external returns (bytes32) {
        if (request.subject == address(0)) revert Bad();
        _seen[request.destination] = request.amount;
        TrustKernelTypes.ActionRequest memory copy = request;
        return _apply(copy);
    }

    function executeRegulatoryReversal(TrustKernelTypes.ReversalRequest calldata request) external {
        if (block.timestamp > request.validBefore) revert Bad();
        _used[request.authorityEpoch] = true;
    }

    function _apply(TrustKernelTypes.ActionRequest memory request) internal returns (bytes32) {
        return keccak256(abi.encode(request.subject, other.subject));
    }

    function ignored(TrustKernelTypes.ActionRequest calldata request) external view returns (bool);

    function _requireCalldataLength(uint256 expected) internal pure {
        assembly ("memory-safe") {
            if xor(calldatasize(), expected) { revert(0, 0) }
        }
    }
}
"""


class CodeMaskTest(unittest.TestCase):
    def test_comments_and_strings_are_not_code(self):
        text = 'a // b\nc "d\\"e" /* f */ g'
        mask = mutation.code_mask(text)
        code = "".join(character for character, keep in zip(text, mask) if keep)
        self.assertEqual(code, "a \nc   g")

    def test_unclosed_comment_is_refused(self):
        with self.assertRaises(mutation.MutationError):
            mutation.code_mask("a /* b")


class FunctionScanTest(unittest.TestCase):
    def test_calldata_request_functions_with_bodies(self):
        found = {item.name: item for item in mutation.calldata_request_functions(SYNTHETIC)}
        self.assertEqual(sorted(found), ["executeRegulatoryAction", "executeRegulatoryReversal"])
        self.assertEqual(found["executeRegulatoryReversal"].struct, "ReversalRequest")
        body = SYNTHETIC[found["executeRegulatoryAction"].body_start:found["executeRegulatoryAction"].body_end]
        self.assertTrue(body.startswith("{") and body.endswith("}"))
        self.assertIn("return _apply(copy);", body)


class TruncatingRewriteTest(unittest.TestCase):
    def test_address_rewrite(self):
        rewritten, detail = mutation.truncating_rewrite(SYNTHETIC, CATALOG, "address")
        self.assertEqual(detail["reads"], {"ActionRequest.destination": 1, "ActionRequest.subject": 1})
        self.assertEqual(detail["memoryCopies"], 1)
        self.assertEqual(detail["functions"], ["executeRegulatoryAction"])
        self.assertIn("if (address(uint160(_wordGuardMutantWord(request, 3))) == address(0)) revert Bad();", rewritten)
        self.assertIn("_seen[address(uint160(_wordGuardMutantWord(request, 5)))] = request.amount;", rewritten)
        self.assertIn("TrustKernelTypes.ActionRequest memory copy = _wordGuardMutantCopy(request);", rewritten)
        self.assertIn("// request.subject in a comment stays", rewritten)
        self.assertIn('"request.subject in a string stays"', rewritten)
        self.assertIn("return keccak256(abi.encode(request.subject, other.subject));", rewritten)
        self.assertIn("copy.subject = address(uint160(_wordGuardMutantWord(request, 3)));", rewritten)
        self.assertIn("copy.amount = request.amount;", rewritten)
        self.assertEqual(rewritten.count("function _wordGuardMutantWord("), 2)
        self.assertLess(rewritten.index("function _wordGuardMutantCopy("), rewritten.index("function _requireCalldataLength("))
        self.assertEqual(mutation.remaining_checked_reads(rewritten, CATALOG, "address"), 0)
        self.assertEqual(mutation.remaining_checked_reads(SYNTHETIC, CATALOG, "address"), 3)

    def test_width_rewrite_of_both_requests(self):
        rewritten, detail = mutation.truncating_rewrite(SYNTHETIC, CATALOG, "uint48")
        self.assertEqual(detail["reads"], {"ReversalRequest.validBefore": 1})
        self.assertIn("block.timestamp > uint48(_wordGuardMutantWord(request, 11))", rewritten)
        self.assertIn("copy.validBefore = uint48(_wordGuardMutantWord(request, 19));", rewritten)
        rewritten, detail = mutation.truncating_rewrite(SYNTHETIC, CATALOG, "uint64")
        self.assertIn("_used[uint64(_wordGuardMutantWord(request, 8))] = true;", rewritten)

    def test_missing_anchor_is_refused(self):
        with self.assertRaises(mutation.MutationError):
            mutation.truncating_rewrite(SYNTHETIC.replace("_requireCalldataLength", "_length"), CATALOG, "address")

    def test_rewrite_is_deterministic(self):
        self.assertEqual(mutation.truncating_rewrite(SYNTHETIC, CATALOG, "address"),
                         mutation.truncating_rewrite(SYNTHETIC, CATALOG, "address"))

    def test_kind_width_rewrite_keeps_the_checked_conversion(self):
        source = SYNTHETIC.replace("        if (request.subject == address(0)) revert Bad();\n",
                                   "        if (request.subject == address(0)) revert Bad();\n"
                                   "        if (request.action == TrustKernelTypes.ActionKind.FREEZE) revert Bad();\n", 1)
        source = source.replace("        _used[request.authorityEpoch] = true;\n",
                                "        _used[request.authorityEpoch] = true;\n"
                                "        _kinds[request.reversalId] = uint8(request.reversal);\n", 1)
        rewritten, detail = mutation.truncating_rewrite(source, CATALOG, "ActionKindWord")
        self.assertEqual(detail["reads"], {"ActionRequest.action": 1})
        self.assertEqual(detail["memoryCopies"], 1)
        self.assertIn("if (TrustKernelTypes.ActionKind(uint8(_wordGuardMutantWord(request, 2))) == "
                      "TrustKernelTypes.ActionKind.FREEZE) revert Bad();", rewritten)
        self.assertIn("copy.action = TrustKernelTypes.ActionKind(uint8(_wordGuardMutantWord(request, 2)));", rewritten)
        self.assertIn("copy.actionId = request.actionId;", rewritten)
        self.assertEqual(mutation.remaining_checked_reads(rewritten, CATALOG, "ActionKindWord"), 0)
        rewritten, detail = mutation.truncating_rewrite(source, CATALOG, "ReversalKindWord")
        self.assertEqual(detail["reads"], {"ReversalRequest.reversal": 1})
        self.assertEqual(detail["memoryCopies"], 0)
        self.assertIn("_kinds[request.reversalId] = uint8(TrustKernelTypes.ReversalKind(uint8(_wordGuardMutantWord("
                      "request, 3))));", rewritten)
        self.assertEqual(mutation.remaining_checked_reads(rewritten, CATALOG, "ReversalKindWord"), 0)

    def test_guard_matching(self):
        self.assertTrue(mutation.guard_matches({"kind": "enum", "bound": 6, "enum": "ActionKind"}, "ActionKindWord"))
        self.assertFalse(mutation.guard_matches({"kind": "enum", "bound": 3, "enum": "ReversalKind"}, "ActionKindWord"))
        self.assertFalse(mutation.guard_matches({"kind": "enum", "bound": 6, "enum": "ActionKind"}, "ActionKind"))
        self.assertTrue(mutation.guard_matches({"kind": "uint64", "width": 64}, "uint64"))
        self.assertFalse(mutation.guard_matches(None, "uint64"))


class EnumWideningTest(unittest.TestCase):
    TYPES = "library T {\n    enum ReversalKind {\n        UNFREEZE,\n        RELEASE,\n        UNRESTRICT\n    }\n}\n"

    def test_widening_gives_256_members(self):
        rewritten, detail = mutation.widen_enum(self.TYPES, "ReversalKind")
        body = re.search(r"enum ReversalKind \{\n(.*?)\n    \}", rewritten, re.S).group(1)
        names = [line.strip().rstrip(",") for line in body.splitlines()]
        self.assertEqual(len(names), 256)
        self.assertEqual(names[:4], ["UNFREEZE", "RELEASE", "UNRESTRICT", "WORD_GUARD_MUTANT_KIND_3"])
        self.assertEqual(names[-1], "WORD_GUARD_MUTANT_KIND_255")
        self.assertEqual(detail, {"enum": "ReversalKind", "declaredMembers": 3, "membersAfter": 256})

    def test_widening_twice_is_refused(self):
        rewritten, _ = mutation.widen_enum(self.TYPES, "ReversalKind")
        with self.assertRaises(mutation.MutationError):
            mutation.widen_enum(rewritten, "ReversalKind")


class ProductSourceTest(unittest.TestCase):
    def test_every_declared_mutant_rewrites_the_current_sources(self):
        mutants = mutation.validate_mutant_list(ROOT, MUTANTS)
        self.assertEqual([row["id"] for row in mutants],
                         ["ADDRESS-WIDTH", "UINT64-WIDTH", "UINT48-WIDTH", "ACTION-KIND-BOUND", "REVERSAL-KIND-BOUND",
                          "ACTION-KIND-WIDTH", "REVERSAL-KIND-WIDTH"])
        for row in mutants:
            record = mutation.expected_rewrite(ROOT, row, CATALOG)
            self.assertTrue(record["files"], row["id"])
            for item in record["files"]:
                self.assertNotEqual(item["beforeSha256"], item["afterSha256"], row["id"])
        for profile, relative in mutation.ENDPOINT_FILES.items():
            text = (ROOT / relative).read_text(encoding="utf-8")
            for guard in mutation.WIDTH_TYPES:
                rewritten, _ = mutation.truncating_rewrite(text, CATALOG, guard)
                self.assertEqual(mutation.remaining_checked_reads(rewritten, CATALOG, guard), 0, (profile, guard))
                if mutation.width_fields(CATALOG, guard)["ActionRequest"]:
                    self.assertEqual(rewritten.count("TrustKernelTypes.ActionRequest memory copy = request;"), 0)

    def test_equivalent_mutant_needs_its_rule_in_the_source(self):
        changed = copy.deepcopy(MUTANTS)
        changed["mutants"][4]["subsumingRule"][0]["snippet"] = "a rule that is not in the source"
        with self.assertRaises(mutation.MutationError):
            mutation.validate_mutant_list(ROOT, changed)

    def test_contract_of_the_list(self):
        for change in (lambda doc: doc["mutants"][0].__setitem__("profiles", ["Native", "Native"]),
                       lambda doc: doc["mutants"][0].__setitem__("guard", "bytes32"),
                       lambda doc: doc["mutants"][1].__setitem__("repinAdapterCreationHash", False),
                       lambda doc: doc["mutants"][3].__setitem__("enum", "CaseFamily"),
                       lambda doc: doc["mutants"][4].pop("rationale"),
                       lambda doc: doc["mutants"][2].__setitem__("expectedVerdict", "SURVIVED"),
                       lambda doc: doc["mutants"].append(copy.deepcopy(doc["mutants"][0]))):
            changed = copy.deepcopy(MUTANTS)
            change(changed)
            with self.assertRaises(mutation.MutationError):
                mutation.validate_mutant_list(ROOT, changed)


class WitnessTableTest(unittest.TestCase):
    def test_witness_table_matches_the_probe(self):
        table = witness_table(CATALOG)
        self.assertEqual(len(table), 68)
        for profile, entrypoints in ENTRYPOINTS.items():
            rows = [row for row in table if row["profile"] == profile]
            self.assertEqual(len(rows), sum(11 if entrypoint in (1, 3) else 6 for entrypoint in entrypoints))
            self.assertEqual(len({row["index"] for row in rows}), len(rows))
        native = {row["index"] for row in table if row["profile"] == "Native"}
        self.assertTrue({1103, 1106, 1110, 1116, 1118, 1119, 1102, WITNESS_BASE + 100 + KIND_CONTROL_WORD,
                         1205, 1208, 1210, 1211, 1203, 1302, 1399, 1403, 1405, 1411,
                         1152, 1253, 1352, 1453} <= native)
        widths = [row for row in table if row["role"] == "kind-width-witness"]
        self.assertEqual(len(widths), 8)
        self.assertEqual({row["guard"] for row in widths}, {"ActionKindWord", "ReversalKindWord"})

    def test_expectations(self):
        table = {(row["profile"], row["index"]): row for row in witness_table(CATALOG)}
        mutants = {row["id"]: row for row in MUTANTS["mutants"]}
        self.assertEqual(expectation(table[("Hook", 1103)], None), "CONFORMS")
        self.assertEqual(expectation(table[("Hook", 1103)], mutants["ADDRESS-WIDTH"]), "DEVIATES")
        self.assertEqual(expectation(table[("Hook", 1103)], mutants["UINT64-WIDTH"]), "CONFORMS")
        self.assertEqual(expectation(table[("Native", 1408)], mutants["UINT64-WIDTH"]), "DEVIATES")
        self.assertEqual(expectation(table[("Partial", 1102)], mutants["ACTION-KIND-BOUND"]), "DEVIATES")
        self.assertEqual(expectation(table[("Partial", 1203)], mutants["REVERSAL-KIND-BOUND"]), "EQUIVALENT")
        self.assertEqual(expectation(table[("Native", 1199)], mutants["ACTION-KIND-BOUND"]), "CONTROL")
        self.assertEqual(expectation(table[("Native", 1152)], mutants["ACTION-KIND-WIDTH"]), "DEVIATES")
        self.assertEqual(expectation(table[("Native", 1152)], mutants["ACTION-KIND-BOUND"]), "CONFORMS")
        self.assertEqual(expectation(table[("Partial", 1102)], mutants["ACTION-KIND-WIDTH"]), "CONFORMS")
        self.assertEqual(expectation(table[("Hook", 1253)], mutants["REVERSAL-KIND-WIDTH"]), "DEVIATES")
        self.assertEqual(expectation(table[("Hook", 1253)], mutants["REVERSAL-KIND-BOUND"]), "CONFORMS")
        self.assertEqual(expectation(table[("Hook", 1203)], mutants["REVERSAL-KIND-WIDTH"]), "CONFORMS")


if __name__ == "__main__":
    unittest.main()
