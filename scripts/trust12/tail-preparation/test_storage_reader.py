#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Unit tests of the storage reader tool on synthetic inputs and, when the public record exists, on its clauses."""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
spec = importlib.util.spec_from_file_location("storage_reader_under_test", HERE / "storage_reader.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)
RECORD = ROOT / "evidence/trust12/runtime-link/tail-preparation/storage-reader-checkpoint-v1.json"
BS = "\\"

THEORY = "\n".join([
    "theory Sample",
    "  imports Main",
    "begin",
    "",
    "definition sample_read :: \"nat " + BS + "<Rightarrow> nat\" where",
    "  \"sample_read st base = (if st base = 0 then None else Some " + BS + "<lparr>a_field = st (base + 1),",
    "     b_field = pw_bits 8 8 (st base)" + BS + "<rparr>)\"",
    "",
    "locale sample_keccak =",
    "  fixes kc :: \"nat " + BS + "<Rightarrow> nat\"",
    "begin",
    "",
    "lemma sample_fields [simp]:",
    "  \"first = 1\"",
    "  \"second = 2\"",
    "  by simp_all",
    "",
    "end",
    "",
    "end",
    ""])


class Terms(unittest.TestCase):
    def test_norm_removes_symbol_backslashes(self):
        self.assertEqual(tool.norm("(" + BS + "<lambda>x.\n   x)"), "(<lambda>x. x)")

    def test_strip_parens_keeps_separate_groups(self):
        self.assertEqual(tool.strip_parens("((a b))"), "a b")
        self.assertEqual(tool.strip_parens("(a) (b)"), "(a) (b)")

    def test_split_and_record_fields(self):
        self.assertEqual(tool.split_top("a = f (x, y), b = {c, d}, e = <lparr>g = 1, h = 2<rparr>"),
                         ["a = f (x, y)", "b = {c, d}", "e = <lparr>g = 1, h = 2<rparr>"])
        self.assertEqual(tool.record_fields("<lparr>a = 1, b = (x, y)<rparr>"), {"a": "1", "b": "(x, y)"})
        with self.assertRaises(tool.SourceError):
            tool.record_fields("<lparr>a = 1, a = 2<rparr>")


class Theories(unittest.TestCase):
    def test_definition_statement_and_context(self):
        theory = tool.Theory("sample", THEORY)
        self.assertEqual(theory.definition("sample_read"),
                         "sample_read st base = (if st base = 0 then None else Some <lparr>a_field = st (base + 1), "
                         "b_field = pw_bits 8 8 (st base)<rparr>)")
        self.assertEqual(theory.statement("sample_fields"), ["first = 1", "second = 2"])
        self.assertIn("locale sample_keccak", theory.context_of(theory.offset("sample_fields")))
        with self.assertRaises(tool.SourceError):
            theory.definition("missing_definition")

    def test_struct_reader(self):
        theory = tool.Theory("sample", THEORY)
        reader = tool.struct_reader("sample_read", theory.definition("sample_read"))
        self.assertEqual(reader["members"]["a_field"], {"stored": True, "word": 1, "bits": [0, 256], "decoders": []})
        self.assertEqual(reader["members"]["b_field"]["bits"], [8, 8])
        self.assertEqual((reader["words"], reader["width"], reader["noneWhen"]), ([0, 1], 2, "st base = 0"))
        with self.assertRaises(tool.SourceError):
            tool.member_location("st (base * 2)")


class ReadForms(unittest.TestCase):
    def test_shared_patterns(self):
        cases = {
            "(<lambda>a. if a <in> psr_holders P then A (psr_slot keccak a 17) else 0)": ("A", 17, "word", 0),
            "(<lambda>a. a <in> psr_holders P <and> pw_bool_of (A (psr_slot keccak a 14 + 2)))": ("A", 14, "bool", 2),
            "A 4": ("A", 4, "word", 0),
            "pw_bits 0 64 (A 5)": ("A", 5, "bits0-64", 0),
        }
        for clause, (account, slot, value, word) in cases.items():
            read = tool.read_form(tool.SHARED_PATTERNS, "field", clause)
            self.assertEqual((read["account"], read["slot"], read["value"], read["word"]), (account, slot, value, word))
        self.assertEqual(tool.read_form(tool.SHARED_PATTERNS, "f", "(<lambda>_ _. 0)")["kind"], "constant")
        with self.assertRaises(tool.SourceError):
            tool.read_form(tool.SHARED_PATTERNS, "f", "(<lambda>a. A (psr_slot keccak a 17))")

    def test_native_patterns(self):
        read = tool.read_form(tool.NATIVE_PATTERNS, "f", "(<lambda>cfg a. pw_struct_read cfg a 8 pw_read_effect_head "
                                                        "empty_head)")
        self.assertEqual((read["slot"], read["value"], read["absent"]), (8, "struct:pw_read_effect_head", "empty_head"))
        read = tool.read_form(tool.NATIVE_PATTERNS, "f", "pw_allowance_read")
        self.assertEqual((read["layout"], read["slot"]), ("nested2", 4))

    def test_disagreement(self):
        read = tool.form("storage", account="adapter", layout="mapping", slot=17, key="argument", word=0, value="word")
        storage = {"slot": 17, "offset": 0, "type": "mapping(address => uint256)"}
        self.assertEqual(tool.disagreement(read, storage, "trust_address " + BS + "<Rightarrow> nat"), [])
        self.assertTrue(tool.disagreement(read, dict(storage, slot=18), "trust_address " + BS + "<Rightarrow> nat"))
        self.assertTrue(tool.disagreement(read, dict(storage, type="mapping(bytes32 => uint256)"),
                                          "trust_address " + BS + "<Rightarrow> nat"))
        self.assertTrue(tool.disagreement(read, dict(storage, type="mapping(address => bool)"),
                                          "trust_address " + BS + "<Rightarrow> nat"))


class Databases(unittest.TestCase):
    def database(self, folder, return_code=0, digest=None, body=b"theory X\nbegin\nend\n"):
        path = Path(folder) / "session.db"
        connection = sqlite3.connect(path)
        try:
            connection.execute("create table isabelle_session_info (session_name text, return_code integer, "
                               "errors blob, output_heap text)")
            connection.execute("create table isabelle_sources (session_name text, name text, digest text, "
                               "compressed integer, body blob)")
            connection.execute("insert into isabelle_session_info values ('S', ?, NULL, 'heap')", (return_code,))
            connection.execute("insert into isabelle_sources values ('S', 'X.thy', ?, 0, ?)",
                               (digest or hashlib.sha1(body).hexdigest(), body))
            connection.commit()
        finally:
            connection.close()
        return path

    def test_completed_session_sources(self):
        with tempfile.TemporaryDirectory() as folder:
            sources = tool.database_sources(self.database(folder))
            self.assertEqual(list(sources.values()), [b"theory X\nbegin\nend\n"])

    def test_incomplete_session_or_digest_mismatch(self):
        for options in ({"return_code": 1}, {"digest": "0" * 40}):
            with tempfile.TemporaryDirectory() as folder:
                with self.assertRaises(tool.SourceError):
                    tool.database_sources(self.database(folder, **options))


@unittest.skipUnless(RECORD.is_file(), "the public record is written by the record writer")
class PublicRecord(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.record = json.loads(RECORD.read_text(encoding="utf-8"))
        cls.public = tool.public_members({name: (ROOT / path).read_text(encoding="utf-8")
                                          for name, path in tool.FORMAL.items()})
        cls.crosswalk = json.loads((ROOT / tool.CROSSWALK).read_text(encoding="utf-8"))

    def recompute(self, clauses):
        forms = tool.reader_forms(clauses, self.public)
        plain = json.loads(json.dumps({key: value for key, value in forms.items() if key != "problems"}))
        return forms, tool.comparison(self.crosswalk, plain, self.public, self.record["layoutWords"])

    def test_record_recomputes(self):
        forms, compared = self.recompute(self.record["readerClauses"])
        self.assertEqual(forms["problems"], [])
        self.assertEqual(compared["mismatches"], [])
        self.assertEqual(json.loads(json.dumps(compared["rows"])), self.record["comparison"]["rows"])

    def test_moved_slot_is_found(self):
        clauses = copy.deepcopy(self.record["readerClauses"])
        old, new = "A (psr_slot keccak a 17) else 0)", "A (psr_slot keccak a 18) else 0)"
        clauses["shared:psr_state"] = clauses["shared:psr_state"].replace(old, new)
        clauses["shared:psr_state_fields"] = [prop.replace(old, new) for prop in clauses["shared:psr_state_fields"]]
        forms, compared = self.recompute(clauses)
        self.assertEqual(forms["problems"], [])
        self.assertTrue(any("custody_backing / ERC3643HookAdapter: slot 18 read" in item
                            for item in compared["mismatches"]))

    def test_changed_helper_is_found(self):
        clauses = copy.deepcopy(self.record["readerClauses"])
        clauses["helper:pw_map_read"] = clauses["helper:pw_map_read"].replace("key slot)) else 0)", "key 0)) else 0)")
        forms, _ = self.recompute(clauses)
        self.assertIn("helper pw_map_read differs from the pinned text", forms["problems"])


if __name__ == "__main__":
    unittest.main()
