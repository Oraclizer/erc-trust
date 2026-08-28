#!/usr/bin/env python3
"""Independent integrity check for the captured SEP-04 transaction fixture.

This checker does not execute KEVM and cannot discharge SEP-04.  It reconstructs
all 14 closed K ports from the raw captured fields, re-derives the two receipt
storage slots from the pinned solc storage layout, rebuilds the calldata with an
independent Cast process, and checks every captured receipt observation.
"""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
from pathlib import Path


ROW_ROOT = Path(__file__).resolve().parent
REPOSITORY_ROOT = ROW_ROOT.parents[3]
FIXTURE_PATH = ROW_ROOT / "fixture.json"
BRIDGE_PATH = ROW_ROOT / "bridge" / "row-bridge.json"
LOCK_PATH = REPOSITORY_ROOT / "formal" / "kevm" / "dependencies.lock.json"
COMPILER_OUTPUT_PATH = (
    REPOSITORY_ROOT
    / "evidence"
    / "end-to-end-refinement"
    / "runtime-binding"
    / "native"
    / "standard-json-output.json"
)
RUNTIME_ROOT = (
    REPOSITORY_ROOT
    / "evidence"
    / "end-to-end-refinement"
    / "runtime-binding"
    / "resolved"
    / "native"
)
ACTION_TUPLE_TYPE = (
    "(bytes32,bytes32,uint8,address,address,address,address,uint256,bytes32,bytes32,bytes32,"
    "bytes32,bytes32,bytes32,bytes32,bytes32,uint64,uint64,uint256,uint48,uint48)"
)
CANONICAL_TOPIC = "0xaadd5db99c0c1f57ce6f82b109958a00899fc4cea03e70fdae7741b9e7050091"
ZERO_WORD = "0x" + "00" * 32


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def canonical_sha256(value: object) -> str:
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    return sha256_bytes(encoded)


def normalize_hex(value: str, byte_length: int | None = None) -> str:
    raw = value[2:] if value.startswith("0x") else value
    require(re.fullmatch(r"[0-9a-fA-F]*", raw) is not None, f"invalid hex: {value}")
    if len(raw) % 2:
        raw = "0" + raw
    if byte_length is not None:
        require(len(raw) <= byte_length * 2, f"hex exceeds {byte_length} bytes: {value}")
        raw = raw.rjust(byte_length * 2, "0")
    return "0x" + raw.lower()


def wsl(*args: str, input_text: str | None = None) -> str:
    completed = subprocess.run(
        ["wsl.exe", "-d", "Ubuntu", "-e", *args],
        cwd=REPOSITORY_ROOT,
        input=input_text,
        text=True,
        check=True,
        capture_output=True,
    )
    return completed.stdout.strip()


def keccak_hex(hex_value: str) -> str:
    result = wsl("cast", "keccak", input_text=normalize_hex(hex_value))
    require(re.fullmatch(r"0x[0-9a-fA-F]{64}", result) is not None, "Cast returned invalid Keccak")
    return result.lower()


def storage_k(storage: dict[str, str]) -> str:
    entries = sorted(
        ((int(slot, 16), int(value, 16)) for slot, value in storage.items() if int(value, 16) != 0),
        key=lambda item: item[0],
    )
    return ".Map" if not entries else " ".join(f"{slot} |-> {value}" for slot, value in entries)


def code_k(address: str, code: str, token: str, dependency: str) -> str:
    if address == token:
        return "#trustTrustTokenRuntime()"
    if address == dependency:
        return "#trustMockBoundDependencyRuntime()"
    return ".Bytes" if code == "0x" else f'#parseByteStack("{code}")'


def accounts_k(accounts: dict[str, dict[str, object]], token: str, dependency: str) -> str:
    rendered: list[str] = []
    for address, account in sorted(accounts.items(), key=lambda item: int(item[0], 16)):
        storage = storage_k(account["storage"])
        rendered.append(
            "\n".join(
                [
                    "<account>",
                    f"  <acctID> {int(address, 16)} </acctID>",
                    f"  <balance> {int(account['balance'], 16)} </balance>",
                    f"  <code> {code_k(address, account['code'], token, dependency)} </code>",
                    f"  <storage> {storage} </storage>",
                    f"  <origStorage> {storage} </origStorage>",
                    "  <transientStorage> .Map </transientStorage>",
                    f"  <nonce> {int(account['nonce'], 16)} </nonce>",
                    "</account>",
                ]
            )
        )
    return "\n".join(rendered)


def complete_logs_k(logs: list[dict[str, object]]) -> str:
    rendered: list[str] = []
    for log in logs:
        topics = ".List" if not log["topics"] else " ".join(
            f"ListItem({int(topic, 16)})" for topic in log["topics"]
        )
        rendered.append(
            f'ListItem({{ {int(log["emitter"], 16)} | {topics} | #parseByteStack("{log["data"]}") }})'
        )
    return " ".join(rendered)


def request_tuple(request: dict[str, str]) -> str:
    order = [
        "domain", "actionId", "action", "subject", "source", "destination", "custodian", "amount",
        "caseId", "scopeHash", "policyCommitment", "provenanceCommitment", "settlementCommitment",
        "proceedsCommitment", "entitlementCommitment", "authorityRef", "authorityEpoch", "policyEpoch",
        "nonce", "validAfter", "validBefore",
    ]
    return "(" + ",".join(str(request[field]) for field in order) + ")"


def derive_receipt_slots(action_id: str, compiler_output: dict[str, object]) -> dict[str, str]:
    layout = compiler_output["contracts"]["implementation/src/TrustToken.sol"]["TrustToken"]["storageLayout"]

    def derive(mapping_label: str) -> str:
        mapping = next(item for item in layout["storage"] if item["label"] == mapping_label)
        mapping_type = layout["types"][mapping["type"]]
        struct_type = layout["types"][mapping_type["value"]]
        member = next(item for item in struct_type["members"] if item["label"] == "receiptHash")
        preimage = action_id + int(mapping["slot"]).to_bytes(32, "big").hex()
        base = int(keccak_hex(preimage), 16)
        return "0x" + (base + int(member["slot"])).to_bytes(32, "big").hex()

    return {
        "actionRecordReceiptSlot": derive("_actions"),
        "receiptRecordReceiptSlot": derive("_receipts"),
    }


fixture_bytes = FIXTURE_PATH.read_bytes()
fixture = json.loads(fixture_bytes)
bridge = json.loads(BRIDGE_PATH.read_text(encoding="utf-8"))
lock = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
compiler_output = json.loads(COMPILER_OUTPUT_PATH.read_text(encoding="utf-8"))

require(fixture["obligationId"] == "SEP-04", "fixture obligation drift")
require(fixture["status"] == "OPEN", "fixture must remain OPEN")
require(fixture["eligibleForDischarge"] is False, "fixture must remain ineligible for discharge")
require("no KEVM" in fixture["claimBoundary"] or "no KEVM" in fixture["claimBoundary"].lower(), "claim boundary drift")

identity = fixture["compilerRuntimeIdentity"]
require(identity["schedule"] == "CANCUN", "schedule drift")
require(identity["kevmDefinitionRevision"] == lock["components"]["kevmSemantics"]["commit"], "KEVM revision drift")
require(identity["solcVersion"] == lock["components"]["solc"]["version"], "solc version drift")
require(identity["solcBinarySha256"] == lock["components"]["solc"]["binarySha256"], "solc hash drift")
require(identity["compilerOutputSha256"] == sha256_bytes(COMPILER_OUTPUT_PATH.read_bytes()), "compiler output hash drift")
require(identity["dependencyLockSha256"] == sha256_bytes(LOCK_PATH.read_bytes()), "dependency lock hash drift")

token = fixture["deployments"]["token"]
dependency = fixture["deployments"]["dependency"]
for label, deployment in (("TrustToken", token), ("MockBoundDependency", dependency)):
    runtime_path = RUNTIME_ROOT / f"{label}.hex"
    runtime_bytes = bytes.fromhex(runtime_path.read_text(encoding="utf-8").strip()[2:])
    require(deployment["runtimeSha256"] == sha256_bytes(runtime_bytes), f"{label} runtime hash drift")
    require(deployment["runtimeByteLength"] == len(runtime_bytes), f"{label} runtime length drift")
    post_code = bytes.fromhex(fixture["postState"]["accounts"][deployment["address"]]["code"][2:])
    require(post_code == runtime_bytes, f"{label} post-state code differs from pinned runtime")
require(token["runtimeSha256"] == bridge["runtimeBinding"]["runtimeSha256"], "SEP-04 runtime identity drift")
require(token["runtimeByteLength"] == bridge["runtimeBinding"]["runtimeByteLength"], "SEP-04 runtime length drift")

pre_accounts = fixture["preState"]["accounts"]
post_accounts = fixture["postState"]["accounts"]
require(fixture["preState"]["canonicalSha256"] == canonical_sha256(pre_accounts), "pre-state hash drift")
require(fixture["postState"]["canonicalSha256"] == canonical_sha256(post_accounts), "post-state hash drift")
sender = fixture["transaction"]["sender"]
require(int(pre_accounts[sender]["nonce"], 16) == int(fixture["transaction"]["senderNonceBefore"]), "pre sender nonce drift")
require(int(post_accounts[sender]["nonce"], 16) == int(fixture["transaction"]["senderNonceAfter"]), "post sender nonce drift")
require(int(fixture["transaction"]["senderNonceAfter"]) == int(fixture["transaction"]["senderNonceBefore"]) + 1, "sender nonce is not +1")

request = fixture["request"]
rebuilt_calldata = normalize_hex(
    wsl("cast", "calldata", f"executeRegulatoryAction({ACTION_TUPLE_TYPE})", request_tuple(request))
)
require(rebuilt_calldata == fixture["transaction"]["calldataHex"], "calldata does not reconstruct exactly")
require(len(bytes.fromhex(rebuilt_calldata[2:])) == 4 + 21 * 32, "ActionRequest calldata length drift")
selector = wsl("cast", "sig", f"executeRegulatoryAction({ACTION_TUPLE_TYPE})").lower()
require(rebuilt_calldata.startswith(selector), "calldata selector drift")

observations = fixture["observations"]
receipt_hash = normalize_hex(observations["receiptHash"], 32)
require(observations["ethCallReturnPayloadHex"] == receipt_hash, "eth_call return drift")
require(observations["returnPayloadHex"] == receipt_hash, "trace return drift")
require(observations["actionRecordReceiptHash"] == receipt_hash, "action record receipt drift")
require(observations["receiptRecordReceiptHash"] == receipt_hash, "receipt record receipt drift")
logs = observations["completeLogs"]
require(logs and [entry["index"] for entry in logs] == list(range(len(logs))), "complete log order/index drift")
final_log = logs[-1]
expected_topics = [
    CANONICAL_TOPIC,
    request["actionId"],
    normalize_hex(hex(int(request["action"])), 32),
    request["caseId"],
]
require(final_log["emitter"] == token["address"], "final log emitter drift")
require(final_log["topics"] == expected_topics, "final log topic/order drift")
require(normalize_hex(final_log["data"], 32) == receipt_hash, "final log data drift")
require(observations["completeLogsK"] == complete_logs_k(logs), "complete log K serialization drift")

derived_slots = derive_receipt_slots(request["actionId"], compiler_output)
storage = fixture["storageObservations"]
require(storage["storageLayoutDerived"] is True, "storage-layout derivation marker missing")
require(storage["actionRecordReceiptSlot"] == derived_slots["actionRecordReceiptSlot"], "action slot drift")
require(storage["receiptRecordReceiptSlot"] == derived_slots["receiptRecordReceiptSlot"], "receipt slot drift")
require(storage["preActionRecordReceiptHash"] == ZERO_WORD, "action receipt existed before execution")
require(storage["preReceiptRecordReceiptHash"] == ZERO_WORD, "receipt record existed before execution")
require(storage["actionRecordReceiptHash"] == receipt_hash, "stored action receipt drift")
require(storage["receiptRecordReceiptHash"] == receipt_hash, "stored receipt drift")
token_storage = post_accounts[token["address"]]["storage"]
require(token_storage[derived_slots["actionRecordReceiptSlot"]] == receipt_hash, "post-state action slot/value absent")
require(token_storage[derived_slots["receiptRecordReceiptSlot"]] == receipt_hash, "post-state receipt slot/value absent")

transaction = fixture["transaction"]
chain = fixture["chain"]
reconstructed_ports = {
    "ACCESSED_ACCOUNTS_K": ".Set",
    "ACCESSED_STORAGE_K": ".Map",
    "BLOCK_GAS_LIMIT_INT": str(chain["blockGasLimit"]),
    "BLOCK_NUMBER_INT": str(chain["actionBlockNumber"]),
    "CALLDATA_HEX": rebuilt_calldata,
    "COMPLETE_LOG_LIST_K": complete_logs_k(logs),
    "POST_ACCOUNTS_K": accounts_k(post_accounts, token["address"], dependency["address"]),
    "PRE_ACCOUNTS_K": accounts_k(pre_accounts, token["address"], dependency["address"]),
    "RETURN_PAYLOAD_HEX": receipt_hash,
    "SENDER_INT": str(int(sender, 16)),
    "SENDER_NONCE_BEFORE_INT": transaction["senderNonceBefore"],
    "TIMESTAMP_INT": str(chain["actionBlockTimestamp"]),
    "TOKEN_ADDRESS_INT": str(int(token["address"], 16)),
    "TX_GAS_LIMIT_INT": transaction["gasLimit"],
}
require(sorted(reconstructed_ports) == sorted(bridge["materialization"]["requiredPorts"]), "required port list drift")
require(fixture["ports"] == reconstructed_ports, "one or more K ports do not reconstruct exactly")
for name, value in reconstructed_ports.items():
    require(isinstance(value, str) and value.strip() and "@@" not in value, f"unclosed port: {name}")

trace = fixture["trace"]
require(trace["failed"] is False, "captured transaction trace failed")
require(trace["structLogCount"] > 0, "captured trace is empty")
require(trace["returnValue"] == receipt_hash, "trace return differs from receipt")
require(trace["accessedBeforeFinalize"]["accounts"], "pre-finalize accessed-account trace is empty")
require(trace["terminalAccessPorts"]["accessedAccounts"] == ".Set", "terminal accessed-account port drift")
require(trace["terminalAccessPorts"]["accessedStorage"] == ".Map", "terminal accessed-storage port drift")
require(transaction["status"] == "0x1", "transaction did not succeed")
require(int(transaction["gasUsed"]) <= int(transaction["gasLimit"]), "gas used exceeds transaction limit")
require(chain["hardfork"] == "cancun" and chain["chainId"] == 31337, "chain context drift")
foundry_commit = lock["components"]["forge"]["commit"]
for tool in ("anvilVersion", "forgeVersion", "castVersion"):
    require(foundry_commit in fixture["tools"][tool], f"{tool} is not the pinned Foundry commit")

print(
    json.dumps(
        {
            "status": "FIXTURE_VALIDATION_PASS_OPEN",
            "eligibleForDischarge": False,
            "obligationId": "SEP-04",
            "fixture": FIXTURE_PATH.relative_to(REPOSITORY_ROOT).as_posix(),
            "fixtureSha256": sha256_bytes(fixture_bytes),
            "transactionHash": transaction["hash"],
            "receiptHash": receipt_hash,
            "completeLogCount": len(logs),
            "preAccountCount": len(pre_accounts),
            "postAccountCount": len(post_accounts),
            "reconstructedPortCount": len(reconstructed_ports),
            "remainingGate": "Positive and semantic-negative KEVM graphs plus Isabelle closure are not run.",
        },
        indent=2,
    )
)
