#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Unit tests of the readers of the registered gate verifier, on synthetic sources and databases only."""
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
VERIFIER = Path(__file__).resolve().parents[1] / "verify_registered_gate_v1.py"
spec = importlib.util.spec_from_file_location("registered_gate_unit", VERIFIER)
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)

THEORY = '''theory Sample_Gate
  imports Main
begin

text \\<open>A prose block that names sorry and eval is not code.\\<close>

definition gate_set :: "nat set" where
  "gate_set = set [1, 2]"

(* a comment that names interpretation is not code *)
lemma gate_size: "card gate_set = 2"
  by simp

context sample_context
begin

definition accepted :: "nat set \\<Rightarrow> nat \\<Rightarrow> bool" where
  "accepted registry value \\<longleftrightarrow> (\\<exists>item \\<in> registry. item = value)"

theorem instance_holds:
  "accepted gate_set 1"
  by (simp add: accepted_def gate_set_def)

theorem structured_holds:
  assumes ONE: "value = 1"
  shows "accepted gate_set value"
  using ONE by (simp add: accepted_def gate_set_def)

end

locale joined_context = left_context + right_context

end
'''


def source(text):
    data = text.encode("utf-8")
    return {"name": "~/x/Sample_Gate.thy", "data": data, "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}


def items(rows):
    return ";".join(rows)


CELL = "Kcell:Runtime_{p}:Runtime_{d}:{o}:Kside_{s}"
RECORD = "Krecord:Runtime_{p}:Kclass_{c}"


def registry_line(rows):
    return "SAMPLE_REGISTRY_LIST count=" + str(len(rows)) + " items=" + items(rows)


class CertificateKeys(unittest.TestCase):
    def test_cells_and_records(self):
        rows = [CELL.format(p="Native", d="Forward", o="Legal_Freeze", s="Applied"),
                CELL.format(p="Native", d="Forward", o="Legal_Freeze", s="Not_Applied"),
                CELL.format(p="Hook", d="Reverse", o="TRUST_UNFREEZE", s="Applied"),
                RECORD.format(p="Partial", c="Action_Dirty_Address")]
        self.assertEqual(v.keys_from_registry_list(registry_line(rows)),
                         ["Native/FREEZE/applied", "Native/FREEZE/not-applied", "Hook/UNFREEZE/applied",
                          "Partial/MALFORMED/action-dirty-address"])

    def test_rejections(self):
        good = CELL.format(p="Native", d="Forward", o="Legal_Freeze", s="Applied")
        for line in ("SAMPLE_REGISTRY_LIST count=2 items=" + good,
                     registry_line([good, good]),
                     registry_line([CELL.format(p="Other", d="Forward", o="Legal_Freeze", s="Applied")]),
                     registry_line([CELL.format(p="Native", d="Reverse", o="Legal_Freeze", s="Applied")]),
                     registry_line([CELL.format(p="Native", d="Forward", o="Legal_Freeze", s="Sideways")]),
                     registry_line([good, "Kother:Runtime_Native:Kclass_Empty_Calldata"]
                                   + ["Kcell2:Runtime_Hook:Runtime_Forward:Legal_Seize:Kside_Applied"])):
            with self.assertRaises(v.CheckError):
                v.keys_from_registry_list(line)

    def test_key_coverage(self):
        keys = ["Native/FREEZE/applied", "Native/FREEZE/not-applied", "Native/MALFORMED/empty-calldata"]
        coverage = v.key_coverage(keys)
        self.assertEqual(coverage["cells"], 1)
        self.assertEqual(coverage["cellWitnesses"], {"applied": 1, "notApplied": 1})
        self.assertEqual(coverage["malformedRequests"]["Native"], 1)
        self.assertEqual(coverage["registeredCertificates"], {"Native": 3, "Partial": 0, "Hook": 0})


class Statements(unittest.TestCase):
    def test_locate_in_theory_and_context(self):
        sources = [source(THEORY)]
        self.assertEqual(v.locate({"name": "Sample_Gate.gate_set", "kind": "definition"}, sources),
                         "gate_set = set [1, 2]")
        self.assertEqual(v.locate({"name": "Sample_Gate.gate_size", "kind": "theorem"}, sources),
                         "card gate_set = 2")
        self.assertEqual(v.locate({"name": "sample_context.instance_holds", "kind": "theorem"}, sources),
                         "accepted gate_set 1")
        self.assertEqual(v.locate({"name": "sample_context.structured_holds", "kind": "theorem"}, sources),
                         'assumes ONE: "value = 1" shows "accepted gate_set value"')
        self.assertEqual(v.locate({"name": "sample_context.accepted", "kind": "definition"}, sources),
                         "accepted registry value <longleftrightarrow> (<exists>item <in> registry. item = value)")
        self.assertEqual(v.locate({"name": "Sample_Gate.joined_context", "kind": "locale"}, sources),
                         "left_context + right_context")

    def test_locate_rejections(self):
        sources = [source(THEORY)]
        for name, kind in (("Sample_Gate.instance_holds", "theorem"), ("other_context.instance_holds", "theorem"),
                           ("sample_context.gate_set", "definition"), ("Sample_Gate.missing", "theorem"),
                           ("Sample_Gate.gate_set", "theorem")):
            with self.assertRaises(v.CheckError):
                v.locate({"name": name, "kind": kind}, sources)
        with self.assertRaises(v.CheckError):
            v.locate({"name": "Sample_Gate.gate_size", "kind": "theorem"}, [source(THEORY), source(THEORY + " ")])

    def test_static_problems(self):
        self.assertEqual(v.static_problems([source(THEORY)]), [])
        for bad in ("  by sorry", "  by eval", "interpretation x: sample_context", "sublocale y: z", "oracle w = v",
                    "  apply (code_simp)"):
            self.assertTrue(v.static_problems([source(THEORY.replace("  by simp\n", bad + "\n", 1))]), bad)


class Markers(unittest.TestCase):
    def test_marker_rules(self):
        good = ["CHECK wall=1 names=3 missing=0 thms=3 joined=true oracles=0 oracle_seconds=0.1",
                "AUDIT ROOT_COUNT=5 NAME_COUNT=4 missing=0 oracles=0 cell_oracles=0 skip=false oracle_names=",
                "SIMP still_active=0 different=0"]
        self.assertEqual(v.marker_problems(good), [])
        for bad in ("X oracles=1", "X cell_oracles=2", "X missing=1", "X joined=false", "X still_active=3",
                    "X different=1", "X skip=true", "X oracles=FAILED_JOIN"):
            self.assertTrue(v.marker_problems([bad]), bad)
        self.assertEqual(v.audit_counts(good), [{"rootCount": 5, "nameCount": 4}])

    def test_session_database(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "sample.db"
            data = THEORY.encode("utf-8")
            connection = sqlite3.connect(path)
            connection.execute("create table isabelle_session_info (session_name text, return_code integer, errors blob, "
                               "input_heaps text, output_heap text)")
            connection.execute("create table isabelle_sources (session_name text, name text, digest text, "
                               "compressed integer, body blob)")
            connection.execute("create table isabelle_exports (session_name text, theory_name text, name text, "
                               "executable integer, compressed integer, body blob)")
            connection.execute("insert into isabelle_session_info values ('S', 0, NULL, ?, ?)",
                               ("a" * 40 + " Parent\n", "b" * 40 + " S\n"))
            connection.execute("insert into isabelle_sources values ('S', '~/x/Sample_Gate.thy', ?, 0, ?)",
                               (hashlib.sha1(data).hexdigest(), data))
            body = "\x05\x06writeln_message\x06serial=1\x05PASS_SAMPLE_ORACLE_ZERO_SKIP_FALSE\x05\x06\x05"
            connection.execute("insert into isabelle_exports values ('S', 'S.Sample_Gate', 'PIDE/messages', 0, 0, ?)",
                               (body.encode("utf-8"),))
            connection.commit()
            connection.close()
            database = v.session_database(path)
            self.assertEqual(database["name"], "S")
            self.assertEqual(database["inputs"], [("a" * 40, "Parent")])
            self.assertEqual(database["messages"]["S.Sample_Gate"]["bodies"], ["PASS_SAMPLE_ORACLE_ZERO_SKIP_FALSE"])
            connection = sqlite3.connect(path)
            connection.execute("update isabelle_sources set digest = ?", ("c" * 40,))
            connection.commit()
            connection.close()
            with self.assertRaises(v.CheckError):
                v.session_database(path)
            connection = sqlite3.connect(path)
            connection.execute("update isabelle_sources set digest = ?", (hashlib.sha1(data).hexdigest(),))
            connection.execute("update isabelle_session_info set return_code = 1")
            connection.commit()
            connection.close()
            with self.assertRaises(v.CheckError):
                v.session_database(path)


class Inputs(unittest.TestCase):
    def test_snapshot_rules(self):
        with tempfile.TemporaryDirectory() as folder:
            theory = Path(folder) / "stage" / "Sample_Gate.thy"
            theory.parent.mkdir()
            theory.write_bytes(THEORY.encode("utf-8"))
            digest = hashlib.sha256(theory.read_bytes()).hexdigest()
            rows = [{"path": str(theory), "sha256": digest}]
            # A stored name is home-relative; its tail after the home folder must end the recorded path.
            stored = [{"name": "~/" + "/".join(Path(theory).parts[-2:]), "sha256": digest}]
            self.assertEqual(len(v.check_inputs(rows, json.loads(json.dumps(rows)), stored, {}, "run")), 1)
            with self.assertRaises(v.CheckError):
                v.check_inputs(rows, [], stored, {}, "run")
            with self.assertRaises(v.CheckError):
                v.check_inputs([{"path": str(theory), "sha256": "0" * 64}], [{"path": str(theory), "sha256": "0" * 64}],
                               [], {}, "run")
            with self.assertRaises(v.CheckError):
                v.check_inputs(rows, rows, [{"name": "~/stage/Other.thy", "sha256": digest}], {}, "run")

    def test_model_rows(self):
        rows = [("C:/a/formal/isabelle/ERC_TRUST/A.thy", "1"), ("C:/a/other/B.thy", "2")]
        self.assertEqual(v.model_rows(rows), {"formal/isabelle/ERC_TRUST/A.thy": "1"})
        with self.assertRaises(v.CheckError):
            v.model_rows(rows + [("C:/b/formal/isabelle/ERC_TRUST/A.thy", "3")])

    def test_symbols_without_backslash(self):
        self.assertEqual(v.collapse("a \\<and>\n   b"), "a <and> b")
        self.assertEqual(v.unquote('"x = y"'), "x = y")
        self.assertEqual(v.unquote('assumes A: "x" shows "y"'), 'assumes A: "x" shows "y"')


if __name__ == "__main__":
    unittest.main()
