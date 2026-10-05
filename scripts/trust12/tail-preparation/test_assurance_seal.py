#!/usr/bin/env python3
"""Positive and negative controls of the Assurance input seal tool on a synthetic tree."""
from __future__ import annotations

import copy
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

import assurance_seal
from tail_common import PreparationError, load_json


def run(root: Path, *arguments: str) -> None:
    subprocess.run(["git", "-C", str(root), *arguments], check=True, capture_output=True)


class SyntheticTree:
    """A tiny product repository and evidence root with the shapes the seal selects."""

    def __init__(self) -> None:
        self.directory = tempfile.TemporaryDirectory(prefix="seal-test-")
        self.base = Path(self.directory.name)
        self.product = self.base / "product"
        self.evidence = self.base / "evidence"
        files = {
            "formal/isabelle/A/ROOT": "session A = HOL\n",
            "formal/isabelle/A/A.thy": "theory A imports Main begin end\n",
            "spec/kernel.json": "{}\n",
            "implementation/src/T.sol": "// SPDX-License-Identifier: BSD-3-Clause\n",
            "foundry.toml": "solc_version = \"0.8.36\"\n",
            "evidence/trust12/ledger.json": "{}\n",
            "scripts/check.py": "print('ok')\n",
            "README.md": "readme\n",
        }
        for path, text in files.items():
            target = self.product / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text, encoding="utf-8", newline="\n")
        run(self.product, "init", "-q")
        run(self.product, "config", "user.name", "Test")
        run(self.product, "config", "user.email", "test@example.invalid")
        run(self.product, "remote", "add", "origin", "https://github.com/Example/product.git")
        run(self.product, "add", "-A")
        run(self.product, "commit", "-q", "-m", "fixture")
        run_root = self.evidence / "cell-one" / "Run01"
        run_root.mkdir(parents=True)
        (self.evidence / "cell-one" / "ROOT").write_text("session CELL = A\n", encoding="utf-8")
        (self.evidence / "cell-one" / "Cell.thy").write_text("theory Cell imports A begin end\n", encoding="utf-8")
        (self.evidence / "support").mkdir()
        (self.evidence / "support" / "ROOT").write_text("session SUPPORT = HOL\n", encoding="utf-8")
        (self.evidence / "support" / "S.thy").write_text("theory S imports Main begin end\n", encoding="utf-8")
        (run_root / "result.json").write_text('{"status": "PASS"}\n', encoding="utf-8")
        support = (self.evidence / "support").resolve().as_posix()
        (run_root / "command.sh").write_text(f"isabelle build -d '{support}' CELL\n", encoding="utf-8")
        (run_root / "heap.bin").write_bytes(b"\0" * 64)
        ledger = {"rows": [{"evidence": {"sourceConsumer": [
            {"kind": "kernel", "countsTowardClosure": True, "root": "cell-one", "run": "Run01"}]}}]}
        (self.evidence / "ledger").mkdir()
        (self.evidence / "ledger" / "obligation-ledger.json").write_text(json.dumps(ledger), encoding="utf-8")
        self.roots = {"PRODUCT": self.product.resolve(), "EVIDENCE": self.evidence.resolve()}

    def spec(self) -> dict:
        template = load_json(assurance_seal.OUTPUT / "assurance-input-seal-spec-v1.json")
        return {
            "schema": assurance_seal.SPEC_SCHEMA,
            "rootInventory": {"PRODUCT": "git-tracked", "EVIDENCE": "walk"},
            "bundles": [
                {"id": "abstract-authority", "centralClosureRole": "abstract authority", "description": "d",
                 "selectors": [{"root": "PRODUCT", "include": ["formal/**"]}]},
                {"id": "implementation-target", "centralClosureRole": "implementation target", "description": "d",
                 "selectors": [{"root": "PRODUCT", "include": ["implementation/**", "foundry.toml"]}]},
                {"id": "runtime-link-evidence", "centralClosureRole": "runtime-link evidence", "description": "d",
                 "selectors": [
                     {"root": "EVIDENCE", "include": ["ledger/obligation-ledger.json"]},
                     {"root": "EVIDENCE", "ledger": "ledger/obligation-ledger.json", "runFiles": ["result.json"],
                      "optionalRunFiles": ["command.sh"], "rootFiles": ["ROOT", "*.thy"],
                      "followSessionDirectories": True}]},
                {"id": "remaining-tracked-files", "centralClosureRole": "remaining tracked files", "description": "d",
                 "selectors": [{"root": "PRODUCT", "remainder": True}]},
            ],
            "toolchain": [{"name": "solc", "pin": "0.8.36", "declaredIn": {"root": "PRODUCT", "path": "foundry.toml"},
                           "declarationText": "solc_version = \"0.8.36\""}],
            "reproduction": template["reproduction"],
            "assuranceChecks": template["assuranceChecks"],
            "reuse": template["reuse"],
            "exclusions": template["exclusions"],
        }

    def close(self) -> None:
        # Git writes its object files read-only. TemporaryDirectory clears that attribute before removing
        # them, so the tree is also removed on Windows, where a plain shutil.rmtree fails on those files.
        self.directory.cleanup()


class AssuranceSealTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tree = SyntheticTree()
        self.seal = assurance_seal.build_seal(self.tree.spec(), self.tree.roots, assurance_seal.DRY_RUN)

    def tearDown(self) -> None:
        self.tree.close()

    def verify(self, seal: dict | None = None) -> dict:
        return assurance_seal.verify_seal(self.seal if seal is None else seal, self.tree.roots)

    def test_seal_covers_every_tracked_file_and_the_cited_evidence(self) -> None:
        self.assertEqual(self.verify()["status"], "PASS_ASSURANCE_INPUT_SEAL_VERIFIED")
        product = {item["path"] for bundle in self.seal["bundles"] for item in bundle["files"] if item["root"] == "PRODUCT"}
        tracked = set(assurance_seal.tracked_files(self.tree.product))
        self.assertEqual(product, tracked)
        evidence = {item["path"] for bundle in self.seal["bundles"] for item in bundle["files"] if item["root"] == "EVIDENCE"}
        self.assertIn("cell-one/Run01/result.json", evidence)
        self.assertIn("cell-one/Run01/command.sh", evidence)
        self.assertIn("support/S.thy", evidence, "session directories loaded by the command are sealed")
        self.assertNotIn("cell-one/Run01/heap.bin", evidence)

    def test_seal_is_deterministic_and_has_no_absolute_path(self) -> None:
        again = assurance_seal.build_seal(self.tree.spec(), self.tree.roots, assurance_seal.DRY_RUN)
        self.assertEqual(json.dumps(self.seal, sort_keys=True), json.dumps(again, sort_keys=True))
        text = json.dumps(self.seal)
        self.assertNotIn(self.tree.base.as_posix(), text)
        self.assertNotIn(str(self.tree.base), text)

    def test_modified_byte_fails(self) -> None:
        (self.tree.product / "implementation/src/T.sol").write_text("// changed\n", encoding="utf-8")
        with self.assertRaisesRegex(PreparationError, "content drift"):
            self.verify()

    def test_modified_evidence_fails(self) -> None:
        (self.tree.evidence / "support" / "S.thy").write_text("theory S imports Main begin (* x *) end\n")
        with self.assertRaisesRegex(PreparationError, "content drift"):
            self.verify()

    def test_added_evidence_theory_fails(self) -> None:
        (self.tree.evidence / "cell-one" / "Extra.thy").write_text("theory Extra imports Main begin end\n")
        with self.assertRaisesRegex(PreparationError, "unsealed file present"):
            self.verify()

    def test_removed_file_fails(self) -> None:
        (self.tree.evidence / "cell-one" / "Run01" / "command.sh").unlink()
        with self.assertRaisesRegex(PreparationError, "sealed file missing"):
            self.verify()

    def test_new_commit_fails(self) -> None:
        (self.tree.product / "NEW.md").write_text("new\n", encoding="utf-8")
        run(self.tree.product, "add", "NEW.md")
        run(self.tree.product, "commit", "-q", "-m", "drift")
        with self.assertRaisesRegex(PreparationError, "product commit drift"):
            self.verify()

    def test_toolchain_declaration_drift_fails(self) -> None:
        seal = copy.deepcopy(self.seal)
        seal["toolchain"][0]["declarationText"] = "solc_version = \"0.8.35\""
        seal["toolchain"][0]["pin"] = "0.8.35"
        with self.assertRaisesRegex(PreparationError, "not declared where the seal says"):
            self.verify(seal)

    def test_tampered_bundle_root_fails(self) -> None:
        seal = copy.deepcopy(self.seal)
        seal["bundles"][0]["rootSha256"] = "0" * 64
        with self.assertRaisesRegex(PreparationError, "bundle root"):
            self.verify(seal)

    def test_overlapping_bundles_are_rejected(self) -> None:
        spec = self.tree.spec()
        spec["bundles"][1]["selectors"][0]["include"].append("formal/**")
        with self.assertRaisesRegex(PreparationError, "sealed by two bundles"):
            assurance_seal.build_seal(spec, self.tree.roots, assurance_seal.DRY_RUN)

    def test_sealed_status_requires_a_clean_worktree(self) -> None:
        (self.tree.product / "README.md").write_text("dirty\n", encoding="utf-8")
        with self.assertRaisesRegex(PreparationError, "clean product worktree"):
            assurance_seal.build_seal(self.tree.spec(), self.tree.roots, assurance_seal.SEALED)

    def test_synthetic_tree_is_removed_completely(self) -> None:
        self.assertTrue(any((self.tree.product / ".git" / "objects").rglob("*")), "the fixture holds Git objects")
        self.tree.close()
        self.assertFalse(self.tree.base.exists(), "the fixture tree, including read-only Git objects, is removed")

    def test_schema_rejects_an_absolute_path(self) -> None:
        seal = copy.deepcopy(self.seal)
        seal["bundles"][0]["files"][0]["path"] = "C:/private/file.thy"
        with self.assertRaisesRegex(PreparationError, "violates its schema"):
            self.verify(seal)


class InputListSealTest(unittest.TestCase):
    """The list selector seals one input list and rechecks every file it names on sealing and on verification."""

    def setUp(self) -> None:
        import assurance_inputs

        self.inputs = assurance_inputs
        self.tree = SyntheticTree()
        private = self.tree.evidence / "private"
        private.mkdir()
        (private / "artifact-index.json").write_text('{"report": "report.json"}\n', encoding="utf-8")
        (private / "report.json").write_text('{"status": "PASS"}\n', encoding="utf-8")
        self.write_list("lists/private.json", self.generator())

    def tearDown(self) -> None:
        self.tree.close()

    def generator(self) -> dict:
        return {"kind": "artifact-index", "tool": {"root": "PRODUCT", "path": self.inputs.TOOL_PATH},
                "index": {"root": "EVIDENCE", "path": "private/artifact-index.json"}, "indexBase": "index"}

    def write_list(self, path: str, generator: dict, document: dict | None = None) -> None:
        document = document or self.inputs.build_list(self.tree.roots, generator, "Synthetic saved-mode inputs.")
        target = self.tree.evidence / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8", newline="\n")

    def spec(self, list_path: str = "lists/private.json") -> dict:
        spec = self.tree.spec()
        spec["bundles"][2]["selectors"].append({"root": "EVIDENCE", "list": list_path})
        return spec

    def seal(self, list_path: str = "lists/private.json") -> dict:
        return assurance_seal.build_seal(self.spec(list_path), self.tree.roots, assurance_seal.DRY_RUN)

    def test_list_file_is_sealed_and_its_entries_are_checked(self) -> None:
        seal = self.seal()
        evidence = {item["path"] for bundle in seal["bundles"] for item in bundle["files"] if item["root"] == "EVIDENCE"}
        self.assertIn("lists/private.json", evidence)
        self.assertNotIn("private/report.json", evidence, "listed files are frozen through the list, not repeated")
        result = assurance_seal.verify_seal(seal, self.tree.roots)
        self.assertEqual(result["status"], "PASS_ASSURANCE_INPUT_SEAL_VERIFIED")
        self.assertEqual(result["listedFiles"], 2)

    def test_listed_file_drift_fails_verification(self) -> None:
        seal = self.seal()
        (self.tree.evidence / "private" / "report.json").write_text('{"status": "FAIL"}\n', encoding="utf-8")
        with self.assertRaisesRegex(PreparationError, "listed input drift"):
            assurance_seal.verify_seal(seal, self.tree.roots)

    def test_listed_file_missing_fails_sealing(self) -> None:
        (self.tree.evidence / "private" / "report.json").unlink()
        with self.assertRaisesRegex(PreparationError, "listed input missing"):
            self.seal()

    def test_list_naming_an_unbound_root_fails(self) -> None:
        document = self.inputs.build_list(self.tree.roots, self.generator(), "Synthetic saved-mode inputs.")
        document["files"][-1]["root"] = "OTHER"
        document["files"].sort(key=lambda item: (item["root"], item["path"]))
        document["rootSha256"] = assurance_seal.tree_root(document["files"])
        self.write_list("lists/unbound.json", self.generator(), document)
        with self.assertRaisesRegex(PreparationError, "unbound root"):
            self.seal("lists/unbound.json")

    def test_list_order_and_root_are_checked(self) -> None:
        document = self.inputs.build_list(self.tree.roots, self.generator(), "Synthetic saved-mode inputs.")
        document["files"].reverse()
        self.write_list("lists/unsorted.json", self.generator(), document)
        with self.assertRaisesRegex(PreparationError, "not sorted and unique"):
            self.seal("lists/unsorted.json")
        document["files"].reverse()
        document["rootSha256"] = "0" * 64
        self.write_list("lists/badroot.json", self.generator(), document)
        with self.assertRaisesRegex(PreparationError, "count or root"):
            self.seal("lists/badroot.json")

    def test_list_path_cannot_leave_its_root(self) -> None:
        with self.assertRaisesRegex(PreparationError, "not a relative path"):
            self.seal("../outside.json")

    def test_list_generated_from_another_ledger_fails(self) -> None:
        document = self.inputs.build_list(self.tree.roots, self.generator(), "Synthetic saved-mode inputs.")
        document["generator"]["ledger"] = {"root": "EVIDENCE", "path": "ledger/old-obligation-ledger.json"}
        self.write_list("lists/old-ledger.json", self.generator(), document)
        with self.assertRaisesRegex(PreparationError, "ledger the seal does not select"):
            self.seal("lists/old-ledger.json")
        document["generator"]["ledger"] = {"root": "EVIDENCE", "path": "ledger/obligation-ledger.json"}
        self.write_list("lists/same-ledger.json", self.generator(), document)
        self.assertEqual(assurance_seal.verify_seal(self.seal("lists/same-ledger.json"), self.tree.roots)["listedFiles"], 2)


if __name__ == "__main__":
    unittest.main()
