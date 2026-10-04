#!/usr/bin/env python3
"""The state and receipt crosswalk binds the regenerated central documents only by the members it reads."""
from __future__ import annotations

import copy
import unittest

import state_receipt_crosswalk as crosswalk
from tail_common import PreparationError, load_json


class ConsumedReferenceTest(unittest.TestCase):
    DOCUMENT = {"stateIdentity": [{"abstract": "balances"}], "receiptIdentity": [{"abiField": "commandId"}],
                "reflection": {"runtimeOnly": [{"item": "x", "reason": "y"}], "statement": "s"},
                "counts": {"rows": 74}, "rows": [{"id": "A", "status": "CLOSED"}]}

    def reference(self, document):
        return crosswalk.consumed_reference(crosswalk.CENTRAL_CLOSURE, document, crosswalk.CLOSURE_MEMBERS)

    def test_unread_members_do_not_change_the_binding(self):
        changed = copy.deepcopy(self.DOCUMENT)
        changed["counts"]["rows"] = 75
        changed["rows"].append({"id": "B", "status": "CURRENT-MANDATORY"})
        changed["reflection"]["statement"] = "another statement"
        self.assertEqual(self.reference(changed), self.reference(self.DOCUMENT))

    def test_read_members_change_the_binding(self):
        for change in (lambda doc: doc["stateIdentity"].append({"abstract": "frozen"}),
                       lambda doc: doc["receiptIdentity"][0].__setitem__("abiField", "receiptKind"),
                       lambda doc: doc["reflection"]["runtimeOnly"][0].__setitem__("reason", "z")):
            changed = copy.deepcopy(self.DOCUMENT)
            change(changed)
            self.assertNotEqual(self.reference(changed)["consumedSha256"], self.reference(self.DOCUMENT)["consumedSha256"])

    def test_missing_member_is_refused(self):
        changed = copy.deepcopy(self.DOCUMENT)
        del changed["reflection"]["runtimeOnly"]
        with self.assertRaises(PreparationError):
            self.reference(changed)

    def test_tracked_crosswalk_binds_the_central_documents_by_their_read_members(self):
        sources = {item["path"]: item for item in load_json(crosswalk.DOCUMENT)["sources"]}
        for path, members in ((crosswalk.CENTRAL_LEDGER, crosswalk.LEDGER_MEMBERS),
                              (crosswalk.CENTRAL_CLOSURE, crosswalk.CLOSURE_MEMBERS)):
            expected = crosswalk.consumed_reference(path, load_json(path), members)
            self.assertEqual(sources[expected["path"]], expected)
            self.assertNotIn("sha256", sources[expected["path"]])


if __name__ == "__main__":
    unittest.main()
