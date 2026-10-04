#!/usr/bin/env python3
"""Positive and negative controls of the typed failure reading, the typed failure probe recorder and the version 2
code identity scan.

The reading, judgement and mutant list controls read tracked product files only. The recorder and load scan controls
need compiled artifacts of the frozen build and run only when the environment variable TRUST12_COMPILED_ARTIFACTS
names a Foundry `out` directory that holds them; no Foundry run is involved.
"""
from __future__ import annotations

import copy
import json
import os
import shutil
import tempfile
import unittest
from pathlib import Path

import code_identity
import code_identity_v2
import run_typed_failure_probe
import typed_failure_report
from tail_common import ROOT, PreparationError, keccak256, load_json, selector, sha256_file

ARTIFACTS = Path(os.environ["TRUST12_COMPILED_ARTIFACTS"]) if os.environ.get("TRUST12_COMPILED_ARTIFACTS") else None
HAS_ARTIFACTS = ARTIFACTS is not None and (ARTIFACTS / "TrustToken.sol" / "TrustToken.json").is_file()
MUTANTS = ROOT / run_typed_failure_probe.MUTANTS


def payload(name: str, *words: int) -> bytes:
    value = selector(next(item["signature"] for item in code_identity.typed_failures() if item["name"] == name))
    return value.to_bytes(4, "big") + b"".join(word.to_bytes(32, "big") for word in words)


class TypedFailureReportTest(unittest.TestCase):
    constants = typed_failure_report.formal_constants()
    command = {"kind": "forward", "commandId": 0x1234, "authorityRef": 0xABCD, "caseId": 0x77}
    sender = 0xB0B

    def test_formal_constants_equal_the_kernel_abi(self) -> None:
        kernel = {item["name"]: int(item["selector"], 16) for item in code_identity.typed_failures()}
        self.assertEqual(self.constants["selectors"], kernel)
        self.assertIn(3, self.constants["reasons"])
        self.assertNotIn(0xFFFF, self.constants["reasons"])

    def test_reading_requires_the_exact_length(self) -> None:
        read = lambda data: typed_failure_report.abi_failure_report(data, self.constants)  # noqa: E731
        self.assertEqual(read(payload("TrustInvalidCommand", 0x1234, 3))["reason"], 3)
        self.assertEqual(read(payload("TrustOperationalFailure", 0x1234, 402, 0x99))["word1"], 0x99)
        self.assertIsNone(read(payload("TrustInvalidCommand", 0x1234, 3, 0)))
        self.assertIsNone(read(payload("TrustReplay", 0x1234, 0)))
        self.assertIsNone(read(b"\x00\x00\x00"))
        self.assertIsNone(read(bytes.fromhex("ffffffff") + bytes(32)))

    def test_binding(self) -> None:
        def binds(data: bytes, command=None, sender=None) -> bool:
            report = typed_failure_report.abi_failure_report(data, self.constants)
            return typed_failure_report.failure_report_binds(report, command or self.command,
                                                             self.sender if sender is None else sender, self.constants)
        self.assertTrue(binds(payload("TrustRejected", 0x1234, 101)))
        self.assertFalse(binds(payload("TrustRejected", 0x1235, 101)))
        self.assertFalse(binds(payload("TrustRejected", 0x1234, 0xFFFF)))
        self.assertTrue(binds(payload("TrustUnauthorized", 0xB0B, 0xABCD)))
        self.assertFalse(binds(payload("TrustUnauthorized", 0xB0B, 0xABCE)))
        self.assertTrue(binds(payload("TrustTerminal", 0x77)))
        self.assertFalse(binds(payload("TrustTerminal", 0x78)))
        self.assertTrue(binds(payload("TrustTerminal", 0x78), {**self.command, "kind": "reverse"}))
        self.assertTrue(binds(payload("TrustReplay", 0x5555)))

    def test_sensitivity_controls_detect_every_mutation(self) -> None:
        for data in (payload("TrustInvalidCommand", 0x1234, 3), payload("TrustOperationalFailure", 0x1234, 402, 1),
                     payload("TrustUnauthorized", 0xB0B, 0xABCD), payload("TrustTerminal", 0x77),
                     payload("TrustReplay", 0x5555)):
            controls = typed_failure_report.sensitivity_controls(data, self.command, self.sender, self.constants)
            self.assertTrue(all(controls.values()), controls)


class TypedFailureJudgementTest(unittest.TestCase):
    """The judgement of one case and the mutant verdict, on synthetic cases without endpoint code."""

    constants = typed_failure_report.formal_constants()

    def case(self, expected, data, entrypoint=1, ok=False, sender=0xB0B):
        return {"index": 101, "profile": "Hook", "entrypoint": entrypoint, "expected": expected, "sender": sender,
                "commandId": 0x1234, "authorityRef": 0xABCD, "caseId": 0x77, "ok": ok, "returnData": data}

    def test_verdicts(self) -> None:
        evaluate = lambda case: run_typed_failure_probe.evaluate(case, self.constants)["verdict"]  # noqa: E731
        self.assertEqual(evaluate(self.case("TrustRejected", payload("TrustRejected", 0x1234, 101))), "BOUND")
        self.assertEqual(evaluate(self.case("TrustRejected", payload("TrustRejected", 0, 101))), "NOT_BOUND")
        self.assertEqual(evaluate(self.case("TrustRejected", payload("TrustInvalidCommand", 0x1234, 3))),
                         "OTHER_TYPED_FAILURE")
        self.assertEqual(evaluate(self.case("TrustRejected", payload("TrustRejected", 0x1234, 101, 0))), "NO_REPORT")
        self.assertEqual(evaluate(self.case("TrustRejected", b"", ok=True)), "UNEXPECTED_SUCCESS")
        self.assertEqual(evaluate(self.case(None, b"", ok=True)), "CONTROL_ACCEPTED")
        self.assertEqual(evaluate(self.case(None, b"", ok=False)), "CONTROL_FAILED")
        self.assertEqual(evaluate(self.case("TrustTerminal", payload("TrustTerminal", 0x99), entrypoint=2)), "BOUND")
        self.assertEqual(evaluate(self.case("TrustTerminal", payload("TrustTerminal", 0x99), entrypoint=1)), "NOT_BOUND")

    def test_mutant_verdict(self) -> None:
        mutant = {"id": "SYNTHETIC", "profile": "Hook", "cases": [101, 102]}
        rows = [{"profile": "Hook", "index": 101, "verdict": "NOT_BOUND"},
                {"profile": "Hook", "index": 102, "verdict": "OTHER_TYPED_FAILURE"}]
        self.assertTrue(run_typed_failure_probe.mutant_verdict(rows, mutant)["detected"])
        rows[1]["verdict"] = "BOUND"
        self.assertFalse(run_typed_failure_probe.mutant_verdict(rows, mutant)["detected"])
        self.assertFalse(run_typed_failure_probe.mutant_verdict(rows[:1], mutant)["detected"])


class TypedFailureMutantListTest(unittest.TestCase):
    def test_every_anchor_occurs_as_declared(self) -> None:
        declared = load_json(MUTANTS)
        self.assertEqual(declared["schema"], run_typed_failure_probe.MUTANTS_SCHEMA)
        for mutant in declared["mutants"]:
            text = (ROOT / mutant["file"]).read_text(encoding="utf-8")
            self.assertEqual(text.count(mutant["old"]), mutant["expectedOccurrences"], mutant["id"])
            self.assertNotEqual(mutant["old"], mutant["new"], mutant["id"])
            self.assertEqual(mutant.get("repinAdapterCreationHash", False),
                             mutant["file"].endswith("ERC3643HookAdapter.sol"), mutant["id"])

    def test_unknown_mutant_fails(self) -> None:
        with self.assertRaisesRegex(PreparationError, "unknown or repeated mutant"):
            run_typed_failure_probe.mutant_definition(MUTANTS, "NO-SUCH-MUTANT")


def encode_case(profile: int, entrypoint: int, expected: int, sender: int, command: int, authority: int,
                case: int, ok: bool, data: bytes) -> str:
    head = [profile, entrypoint, expected, sender, command, authority, case, int(ok), 9 * 32]
    tail = len(data).to_bytes(32, "big") + data + bytes(-len(data) % 32)
    return "0x" + (b"".join(word.to_bytes(32, "big") for word in head) + tail).hex()


def encode_code(endpoint: int, code: bytes) -> str:
    tail = len(code).to_bytes(32, "big") + code + bytes(-len(code) % 32)
    return "0x" + (endpoint.to_bytes(32, "big") + (64).to_bytes(32, "big") + tail).hex()


@unittest.skipUnless(HAS_ARTIFACTS, "TRUST12_COMPILED_ARTIFACTS names no compiled artifacts")
class TypedFailureRecorderTest(unittest.TestCase):
    """Judges a synthetic forge report; no forge run is involved."""

    AUTHORITY = int.from_bytes(keccak256(b"ERC3643-AUTHORITY"), "big")
    SENDER = 0x7FA9385BE102AC3EAC297483DD6233D62B3E1496
    STRANGER = 0x5157

    def synthetic_report(self) -> dict:
        case_topic = run_typed_failure_probe.topic(run_typed_failure_probe.CASE_EVENT)
        code_topic = run_typed_failure_probe.topic(run_typed_failure_probe.CODE_EVENT)
        endpoints = {1: ("TrustToken.sol", "TrustToken"), 2: ("ERC3643TrustAdapter.sol", "ERC3643TrustAdapter"),
                     3: ("ERC3643HookAdapter.sol", "ERC3643HookAdapter")}
        names = ["control", "TrustInvalidCommand", "TrustRejected", "TrustOperationalFailure", "TrustUnauthorized",
                 "TrustReplay", "TrustTerminal"]
        suites = {}
        for profile, (source, name) in endpoints.items():
            code = bytes.fromhex(load_json(ARTIFACTS / source / f"{name}.json")["deployedBytecode"]["object"][2:])
            logs = [{"topics": [code_topic, f"0x{profile:064x}"], "data": encode_code(0x1000 + profile, code)}]
            index = 100
            for entrypoint in (1, 2):
                for expected, failure in enumerate(names):
                    index += 1
                    command, case = 0x1000 + index, (0x2000 + index if entrypoint == 1 else 0)
                    sender = self.STRANGER if failure == "TrustUnauthorized" else self.SENDER
                    words = {"control": None, "TrustInvalidCommand": (command, 3), "TrustRejected": (command, 101),
                             "TrustOperationalFailure": (command, 402, 0x42), "TrustUnauthorized": (sender, self.AUTHORITY),
                             "TrustReplay": (command,), "TrustTerminal": (case or 0x99,)}[failure]
                    data = b"" if words is None else payload(failure, *words)
                    logs.append({"topics": [case_topic, f"0x{index:064x}"],
                                 "data": encode_case(profile, entrypoint, expected, sender, command, self.AUTHORITY,
                                                     case, words is None, data)})
            suites[f"probe.t.sol:Probe{profile}"] = {"test_results": {"testProbe()": {"status": "Success", "logs": logs}}}
        return suites

    def record(self, report, mutant=None):
        return run_typed_failure_probe.record(report, {"command": "synthetic", "exitCode": 0}, "synthetic", "0" * 64,
                                              mutant)

    def test_complete_synthetic_report_is_bound(self) -> None:
        receipt = self.record(self.synthetic_report())
        self.assertEqual(receipt["status"], "PROBE_RECORDED_ALL_BOUND", receipt["summary"])
        self.assertTrue(all(item["matches"] for item in receipt["codeIdentity"].values()))

    def test_unbound_payload_is_reported(self) -> None:
        report = self.synthetic_report()
        # The third log is the TrustInvalidCommand case of the Hook action entrypoint; flip the last byte of word 0 of
        # its payload (nine head words, the length word, the selector, then word 0).
        log = report["probe.t.sol:Probe3"]["test_results"]["testProbe()"]["logs"][2]
        data = bytearray(bytes.fromhex(log["data"][2:]))
        data[9 * 32 + 32 + 4 + 31] ^= 1
        log["data"] = "0x" + data.hex()
        self.assertEqual(self.record(report)["status"], "PROBE_BINDING_FAILED")
        mutant = {"id": "SYNTHETIC", "profile": "Hook", "cases": [102]}
        self.assertEqual(self.record(report, mutant)["status"], "MUTANT_DETECTED")
        self.assertEqual(self.record(self.synthetic_report(), mutant)["status"], "MUTANT_SURVIVED")

    def test_failed_exit_code_is_a_harness_failure(self) -> None:
        receipt = run_typed_failure_probe.record(self.synthetic_report(), {"command": "synthetic", "exitCode": 1},
                                                 "synthetic", "0" * 64)
        self.assertEqual(receipt["status"], "PROBE_HARNESS_FAILED")


@unittest.skipUnless(HAS_ARTIFACTS, "TRUST12_COMPILED_ARTIFACTS names no compiled artifacts")
class CodeIdentityV2Test(unittest.TestCase):
    NAMES = {"TrustToken": "TrustToken.sol", "ERC3643TrustAdapter": "ERC3643TrustAdapter.sol",
             "ProfileGovernor": "ProfileGovernor.sol", "ERC3643HookAdapter": "ERC3643HookAdapter.sol",
             "ERC3643HookGovernor": "ERC3643HookGovernor.sol", "ERC3643HookCompliance": "ERC3643HookCompliance.sol",
             "ERC3643HookFactory": "ERC3643HookFactory.sol"}

    def copy_artifacts(self, root: Path) -> None:
        for name, source in self.NAMES.items():
            (root / source).mkdir(parents=True)
            shutil.copyfile(ARTIFACTS / source / f"{name}.json", root / source / f"{name}.json")

    def build_record(self, root: Path) -> dict:
        artifacts = {f"{source}/{name}.json": sha256_file(root / source / f"{name}.json") for name, source in self.NAMES.items()}
        return {"schema": code_identity_v2.BUILD_RECORD_SCHEMA, "exitCode": 0, "forgeVersion": "synthetic",
                "artifacts": artifacts, "sha256": "0" * 64}

    def test_supplied_build_closes(self) -> None:
        document = code_identity_v2.build(ARTIFACTS, "closure", code_identity.DOCUMENT)
        self.assertEqual(document["status"], "PASS_TYPED_FAILURE_LOADS_RECOMPUTED")
        for row in document["endpointLoads"].values():
            self.assertEqual(row["missing"], [])
            self.assertTrue(all(count >= 1 for count in row["loads"].values()))

    def test_build_record_binds_the_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.copy_artifacts(root)
            record = self.build_record(root)
            document = code_identity_v2.build(root, "closure", code_identity.DOCUMENT, record)
            self.assertEqual(document["buildRecord"]["forgeVersion"], "synthetic")
            record["artifacts"]["TrustToken.sol/TrustToken.json"] = "0" * 64
            with self.assertRaisesRegex(PreparationError, "not the one the build record lists"):
                code_identity_v2.build(root, "closure", code_identity.DOCUMENT, record)

    def test_removed_load_is_detected(self) -> None:
        document = code_identity_v2.build(ARTIFACTS, "prepare", None)
        runtimes = copy.deepcopy(document["runtimes"])
        native = load_json(ARTIFACTS / "TrustToken.sol" / "TrustToken.json")["deployedBytecode"]["object"]
        code = bytearray(bytes.fromhex(native.removeprefix("0x")))
        terminal = runtimes["TrustToken"]["typedFailureSelectorLoads"]["TrustTerminal"]
        self.assertTrue(terminal["push4"])
        for offset in terminal["push4"]:
            code[offset + 1:offset + 5] = b"\x00\x00\x00\x01"
        loads = code_identity.selector_occurrences(bytes(code), 0xA6E257C3)
        runtimes["TrustToken"]["loadCounts"]["TrustTerminal"] = sum(len(value) for value in loads.values())
        matrix = code_identity_v2.endpoint_matrix(runtimes, document["typedFailures"])
        self.assertEqual(matrix["Native"]["missing"], ["TrustTerminal"])

    def test_tampered_runtime_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.copy_artifacts(root)
            path = root / "TrustToken.sol" / "TrustToken.json"
            artifact = load_json(path)
            code = artifact["deployedBytecode"]["object"].removeprefix("0x")
            artifact["deployedBytecode"]["object"] = "0x" + code[:-2] + ("00" if code[-2:] != "00" else "01")
            path.write_text(json.dumps(artifact), encoding="utf-8")
            with self.assertRaisesRegex(PreparationError, "not the frozen template"):
                code_identity_v2.build(root, "prepare", None)

    def test_foreign_source_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.copy_artifacts(root)
            path = root / "ERC3643HookAdapter.sol" / "ERC3643HookAdapter.json"
            artifact = load_json(path)
            source = "implementation/src/profiles/ERC3643HookAdapter.sol"
            artifact["metadata"]["sources"][source]["keccak256"] = "0x" + "00" * 32
            path.write_text(json.dumps(artifact), encoding="utf-8")
            with self.assertRaisesRegex(PreparationError, "differs from the bound input"):
                code_identity_v2.build(root, "prepare", None)

    def test_recorded_difference_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            recorded = load_json(code_identity.DOCUMENT)
            loads = recorded["compiledScan"]["runtimes"]["ERC3643HookAdapter"]["typedFailureSelectorLoads"]
            loads["TrustReplay"]["push4"] = loads["TrustReplay"]["push4"][:-1]
            path = Path(directory) / "recorded.json"
            path.write_text(json.dumps(recorded), encoding="utf-8")
            document = code_identity_v2.build(ARTIFACTS, "prepare", path)
            self.assertFalse(document["recordedComparison"]["equal"])
            self.assertEqual(document["status"], "LOADS_RECOMPUTED_CRITERIA_OPEN")


if __name__ == "__main__":
    unittest.main()
