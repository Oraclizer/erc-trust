#!/usr/bin/env python3
"""Positive and negative controls of the Assurance input list tool on a synthetic tree."""
from __future__ import annotations

import hashlib
import json
import shutil
import sys
import tempfile
import types
import unittest
from pathlib import Path

import assurance_inputs
from tail_common import PreparationError, dump_json, load_json


class InputListTest(unittest.TestCase):
    def setUp(self) -> None:
        self.base = Path(tempfile.mkdtemp(prefix="inputs-test-"))
        self.product = self.base / "product"
        self.evidence = self.base / "evidence"
        (self.product / "scripts").mkdir(parents=True)
        files = {
            "registry/artifact-index.json": '{"certificate-registry": "registry.json", "certificate-locators": "locators.json"}\n',
            "registry/registry.json": "REBUILT\n",
            "registry/locators.json": '{"ledger": "ledger/obligation-ledger.json"}\n',
            "ledger/obligation-ledger.json": '{"rows": []}\n',
            "worlds/ab.kore": "world\n",
            "receipts/BASELINE/receipt.json": "{}\n",
            "receipts/ONE/receipt.json": "{}\n",
            "receipts/ONE/run.log": "log\n",
            "stage/index.json": '{"native": "stage/native.thy"}\n',
            "stage/native.thy": "theory native begin end\n",
        }
        for path, text in files.items():
            target = self.evidence / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text, encoding="utf-8", newline="\n")
        self.roots = {"PRODUCT": self.product.resolve(), "EVIDENCE": self.evidence.resolve()}
        self.tool = {"root": "PRODUCT", "path": assurance_inputs.TOOL_PATH}

    def tearDown(self) -> None:
        sys.modules.pop("certificate_registry_v2", None)
        shutil.rmtree(self.base, ignore_errors=True)

    def fake_registry(self, stored_matches: bool = True) -> None:
        module = types.ModuleType("certificate_registry_v2")

        def build(evidence, locators, mode, source, product, reads):
            self.assertEqual(mode, "closure")
            reads.update({locators["ledger"], "worlds/a:b.kore"})
            return {"rebuilt": stored_matches}

        module.build = build
        module.locator_identity = lambda path: {"sha256": "0" * 64, "bytes": path.stat().st_size}
        module.dump_json = lambda value: "REBUILT\n" if value["rebuilt"] else "OTHER\n"
        sys.modules["certificate_registry_v2"] = module

    def test_index_list_names_the_index_and_every_indexed_file(self) -> None:
        generator = {"kind": "artifact-index", "tool": self.tool, "indexBase": "index",
                     "index": {"root": "EVIDENCE", "path": "registry/artifact-index.json"}}
        document = assurance_inputs.build_list(self.roots, generator, "Registry index.")
        self.assertEqual([item["path"] for item in document["files"]],
                         ["registry/artifact-index.json", "registry/locators.json", "registry/registry.json"])
        root_based = {"kind": "artifact-index", "tool": self.tool, "indexBase": "root",
                      "index": {"root": "EVIDENCE", "path": "stage/index.json"}}
        self.assertEqual([item["path"] for item in assurance_inputs.build_list(self.roots, root_based, "Stage.")["files"]],
                         ["stage/index.json", "stage/native.thy"])

    def test_directory_list_follows_its_pattern(self) -> None:
        generator = {"kind": "directory", "tool": self.tool, "pattern": "*/receipt.json",
                     "directory": {"root": "EVIDENCE", "path": "receipts"}}
        document = assurance_inputs.build_list(self.roots, generator, "Receipts.")
        self.assertEqual([item["path"] for item in document["files"]],
                         ["receipts/BASELINE/receipt.json", "receipts/ONE/receipt.json"])

    def test_regeneration_detects_a_newly_read_file(self) -> None:
        generator = {"kind": "directory", "tool": self.tool, "pattern": "*/receipt.json",
                     "directory": {"root": "EVIDENCE", "path": "receipts"}}
        recorded = dump_json(assurance_inputs.build_list(self.roots, generator, "Receipts."))
        (self.evidence / "receipts/TWO").mkdir()
        (self.evidence / "receipts/TWO/receipt.json").write_text("{}\n", encoding="utf-8")
        self.assertNotEqual(dump_json(assurance_inputs.build_list(self.roots, generator, "Receipts.")), recorded)

    def test_registry_reads_use_the_stored_spelling_and_name_the_ledger(self) -> None:
        self.fake_registry()
        generator = {"kind": "recomputation-reads", "tool": self.tool, "recomputation": "certificate-registry",
                     "index": {"root": "EVIDENCE", "path": "registry/artifact-index.json"}}
        document = assurance_inputs.build_list(self.roots, generator, "Registry reads.")
        paths = [item["path"] for item in document["files"]]
        self.assertIn("worlds/ab.kore", paths, "a colon written by a Linux tool is stored as U+F03A")
        self.assertIn("ledger/obligation-ledger.json", paths)
        self.assertEqual(document["generator"]["ledger"], {"root": "EVIDENCE", "path": "ledger/obligation-ledger.json"})

    def test_registry_reads_refuse_a_stored_registry_that_differs(self) -> None:
        self.fake_registry(stored_matches=False)
        generator = {"kind": "recomputation-reads", "tool": self.tool, "recomputation": "certificate-registry",
                     "index": {"root": "EVIDENCE", "path": "registry/artifact-index.json"}}
        with self.assertRaisesRegex(PreparationError, "differs from the stored registry"):
            assurance_inputs.build_list(self.roots, generator, "Registry reads.")

    def registered_gate_tree(self) -> dict:
        maintainer = self.base / "maintainer"
        maintainer.mkdir()
        (maintainer / "policy.sh").write_text("policy\n", encoding="utf-8")
        (self.evidence / "sources").mkdir()
        (self.evidence / "sources/A.thy").write_text("theory A begin end\n", encoding="utf-8")
        rows = [{"path": "<run-local-catalog>", "sha256": "0" * 64}]
        for path in (self.evidence / "sources/A.thy", maintainer / "policy.sh"):
            rows.append({"path": str(path.resolve()), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
        run = self.evidence / "gate/runs/one"
        run.mkdir(parents=True)
        (run / "inputs-before.json").write_text(json.dumps(rows), encoding="utf-8")
        (run / "result.json").write_text("{}\n", encoding="utf-8")
        (self.evidence / "gate/artifact-index.json").write_text(
            json.dumps({"one-inputs-before": "runs/one/inputs-before.json", "one-result": "runs/one/result.json"}),
            encoding="utf-8")
        return {"kind": "recomputation-reads", "tool": self.tool, "recomputation": "registered-gate",
                "index": {"root": "EVIDENCE", "path": "gate/artifact-index.json"}}

    def test_registered_gate_lists_every_recorded_run_input_by_root(self) -> None:
        generator = self.registered_gate_tree()
        roots = {**self.roots, "MAINTAINER": (self.base / "maintainer").resolve()}
        document = assurance_inputs.build_list(roots, generator, "Registered gate run inputs.")
        names = [(item["root"], item["path"]) for item in document["files"]]
        self.assertIn(("EVIDENCE", "sources/A.thy"), names)
        self.assertIn(("MAINTAINER", "policy.sh"), names)
        self.assertIn(("EVIDENCE", "gate/runs/one/inputs-before.json"), names)
        (self.evidence / "sources/A.thy").write_text("theory A begin (* changed *) end\n", encoding="utf-8")
        with self.assertRaisesRegex(PreparationError, "recorded run input drift"):
            assurance_inputs.build_list(roots, generator, "Registered gate run inputs.")

    def test_registered_gate_input_outside_every_bound_root_fails(self) -> None:
        generator = self.registered_gate_tree()
        with self.assertRaisesRegex(PreparationError, "outside every bound evidence root"):
            assurance_inputs.build_list(self.roots, generator, "Registered gate run inputs.")

    def test_index_path_cannot_leave_its_root(self) -> None:
        generator = {"kind": "artifact-index", "tool": self.tool, "indexBase": "index",
                     "index": {"root": "EVIDENCE", "path": "../outside.json"}}
        with self.assertRaisesRegex(PreparationError, "not a relative path"):
            assurance_inputs.build_list(self.roots, generator, "Outside.")

    def test_tool_refuses_a_foreign_product_tree(self) -> None:
        with self.assertRaisesRegex(PreparationError, "not the tool of the bound product tree"):
            assurance_inputs.main(["check", "--list", str(self.evidence / "none.json"),
                                   "--root", f"PRODUCT={self.product}", "--root", f"EVIDENCE={self.evidence}"])

    def test_list_document_follows_its_schema(self) -> None:
        generator = {"kind": "directory", "tool": self.tool, "pattern": "*/receipt.json",
                     "directory": {"root": "EVIDENCE", "path": "receipts"}}
        document = assurance_inputs.build_list(self.roots, generator, "Receipts.")
        self.assertEqual(document["schema"], "trust12-tail-preparation-assurance-input-list-v1")
        self.assertEqual(document["fileCount"], len(document["files"]))
        self.assertEqual(json.loads(dump_json(document)), document)
        schema = load_json(assurance_inputs.LIST_SCHEMA_DOCUMENT)
        self.assertEqual(schema["$id"], document["schema"])


if __name__ == "__main__":
    unittest.main()
