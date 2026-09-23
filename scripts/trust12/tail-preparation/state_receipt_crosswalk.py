#!/usr/bin/env python3
"""Trace the abstract state and receipt fields to the storage, ABI and events of every profile runtime.

State and receipt identity asks that abstract state, authorization, nonce, terminality and receipt
fields be traced both ways to the actual source, ABI, storage, event and return data. This tool
builds that crosswalk from machine sources only:

* the abstract records of the formal model (the compositional state, its sub-records and the
  compositional receipt),
* the state and receipt identity tables that the conditional central ledger binds for the Native
  and Partial runtimes,
* the compiled storage layouts of all seven profile runtimes from the tracked runtime binding,
* the kernel schema, the receipt JSON schema and the kernel ABI events.

A Hook column is derived only where the Hook runtime has the same storage label, slot, offset and
type as the Partial runtime it was derived from, and is marked as derived rather than reviewed.
Storage that no abstract field reads is listed per runtime with the reflection reason the earlier
central closure gave, or as open.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Any

from tail_common import (
    NONCLAIM, OUTPUT, PROFILE_RUNTIMES, ROOT, PreparationError, dump_json, file_reference, load_json,
    require, write_or_check,
)

DOCUMENT = OUTPUT / "state-receipt-crosswalk-v1.json"
STATE_THEORY = ROOT / "formal/isabelle/ERC_TRUST/TRUST_Compositional_State.thy"
CENTRAL_LEDGER = ROOT / "evidence/end-to-end-refinement/obligation-ledger-v3.json"
CENTRAL_CLOSURE = ROOT / "evidence/end-to-end-refinement/central-closure-v3.json"
KERNEL_SCHEMA = ROOT / "spec/erc-trust-kernel-v2.json"
KERNEL_ABI = ROOT / "spec/generated/kernel-v2-abi.json"
RECEIPT_SCHEMA = ROOT / "schemas/receipt.schema.json"
BINDING = {"Native": "native", "Partial": "erc3643-partial", "Hook": "erc3643-hook"}
COLUMNS = {"native": "TrustToken", "profileAdapter": "ERC3643TrustAdapter", "profileGovernor": "ProfileGovernor"}
DERIVED = {"ERC3643HookAdapter": "ERC3643TrustAdapter", "ERC3643HookGovernor": "ProfileGovernor"}
SUB_RECORDS = {"compositional_receipt": "Receipt", "compositional_action_record": "ActionRecord",
               "compositional_case": "CaseRecord"}
CONTROL_FIELDS = {
    "authorization": ["authorities", "compositional_bindings"],
    "nonce": ["compositional_consumed_nonces"],
    "terminality": ["case_records"],
    "dependency currency": ["dependency_root", "dependency_epoch"],
    "receipt": ["compositional_receipts"],
}


def records(text: str) -> dict[str, list[dict[str, str]]]:
    found = {}
    for match in re.finditer(r"^record (\w+) =\n((?:  \w+ :: .+\n)+)", text, re.MULTILINE):
        fields = re.findall(r"^  (\w+) :: (.+)$", match.group(2), re.MULTILINE)
        found[match.group(1)] = [{"name": name, "type": kind.strip().strip('"')} for name, kind in fields]
    return found


def layouts() -> dict[str, list[dict[str, Any]]]:
    result = {}
    for profile in PROFILE_RUNTIMES:
        for entry in load_json(ROOT / "evidence/runtime-binding-v3" / BINDING[profile] / "bridge-artifacts.json"):
            result[entry["contract"]] = [
                {"label": item["label"], "slot": int(item["slot"]), "offset": item["offset"], "type": item["type"]["label"]}
                for item in entry["storageLayout"]
            ]
    require(sorted(result) == sorted(name for names in PROFILE_RUNTIMES.values() for name in names), "layout set drift")
    return result


def projection_label(projection: str) -> str:
    return "_" + projection.rsplit(".", 1)[1]


def storage_reference(layout: list[dict[str, Any]], projection: str | None) -> dict[str, Any] | None:
    if projection is None:
        return None
    label = projection_label(projection)
    matches = [item for item in layout if item["label"] == label]
    require(len(matches) == 1, f"projection {projection} names no unique storage variable")
    return {"projection": projection, **matches[0]}


def build() -> dict[str, Any]:
    theory = records(STATE_THEORY.read_text(encoding="utf-8"))
    ledger, closure = load_json(CENTRAL_LEDGER), load_json(CENTRAL_CLOSURE)
    require(ledger["stateIdentity"] == closure["stateIdentity"], "central ledger and closure disagree on state identity")
    require(ledger["receiptIdentity"] == closure["receiptIdentity"], "central ledger and closure disagree on receipt identity")
    schema, abi, receipt_schema = load_json(KERNEL_SCHEMA), load_json(KERNEL_ABI), load_json(RECEIPT_SCHEMA)
    layout = layouts()

    state_fields = [field["name"] for field in theory["trust_compositional_state"]]
    identity = {row["abstract"]: row for row in ledger["stateIdentity"]}
    require(sorted(identity) == sorted(state_fields), "state identity rows differ from the abstract state fields")
    state_rows, used = [], {name: set() for name in layout}
    for field in theory["trust_compositional_state"]:
        row = identity[field["name"]]
        columns = {}
        for column, contract in COLUMNS.items():
            reference = storage_reference(layout[contract], row.get(column))
            columns[contract] = {"status": "BOUND_BY_CENTRAL_LEDGER" if reference else "NO_STORAGE", "storage": reference}
            if reference:
                used[contract].add(reference["label"])
        for hook, legacy in DERIVED.items():
            reference = columns[legacy]["storage"]
            if reference is None:
                columns[hook] = {"status": "NO_STORAGE", "storage": None}
                continue
            twin = [item for item in layout[hook] if item["label"] == reference["label"]]
            same = len(twin) == 1 and all(twin[0][key] == reference[key] for key in ("slot", "offset", "type"))
            columns[hook] = {"status": "DERIVED_BY_LAYOUT_IDENTITY" if same else "OPEN",
                             "storage": {"projection": None, **twin[0]} if same else None}
            if same:
                used[hook].add(reference["label"])
        state_rows.append({"abstract": field["name"], "abstractType": field["type"], "note": row.get("note"),
                           "runtimes": columns})

    runtime_only = closure["reflection"]["runtimeOnly"]
    unmapped = {}
    for contract, items in layout.items():
        rows = []
        for item in items:
            if item["label"] in used[contract]:
                continue
            names = {item["label"], item["label"].lstrip("_")}
            reasons = [entry["reason"] for entry in runtime_only
                       if any(re.search(rf"(?<![A-Za-z0-9_]){re.escape(name)}(?![A-Za-z0-9_])", entry["item"])
                              for name in names)]
            rows.append({**item, "reflection": reasons[0] if reasons else None,
                         "status": "RUNTIME_ONLY_BY_EARLIER_CLOSURE" if reasons else "OPEN"})
        unmapped[contract] = rows

    sub_records = []
    for record, struct in SUB_RECORDS.items():
        abstract = [field["name"] for field in theory[record]]
        concrete = [field["name"] for field in schema["structs"][struct]["fields"]]
        require(len(abstract) == len(concrete), f"{record} and {struct} differ in length")
        sub_records.append({"abstract": record, "kernelStruct": struct,
                            "fields": [{"abstract": a, "kernel": c} for a, c in zip(abstract, concrete)]})

    receipt_fields = [field["name"] for field in schema["structs"]["Receipt"]["fields"]]
    require(receipt_schema["required"] == receipt_fields, "receipt JSON schema and kernel schema differ")
    receipt_output = next(item for item in abi["abi"] if item["type"] == "function" and item["name"] == "receipt")
    require([item["name"] for item in receipt_output["outputs"][0]["components"]] == receipt_fields,
            "kernel ABI receipt view and kernel schema differ")
    positional = [{"abiField": c, "abstract": a} for a, c in
                  zip([field["name"] for field in theory["compositional_receipt"]], receipt_fields)]
    require(positional == ledger["receiptIdentity"], "receipt identity is not the positional pairing")
    event_fields = {
        "RegulatoryActionApplied": {"actionId": "commandId", "action": "commandKind"},
        "RegulatoryReversalApplied": {"reversalId": "commandId", "reversal": "commandKind", "actionId": "parentCommandId"},
    }
    events = {}
    for item in (item for item in abi["abi"] if item["type"] == "event" and item["name"] in event_fields):
        events[item["name"]] = [{
            "input": field["name"],
            "indexed": bool(field.get("indexed")),
            "receiptField": event_fields[item["name"]].get(field["name"], field["name"]),
        } for field in item["inputs"]]
    require(sorted(events) == sorted(event_fields), "kernel ABI lacks a regulatory event")
    for rows in events.values():
        require(all(row["receiptField"] in receipt_fields for row in rows), "an event field is not a receipt field")

    return {
        "schema": "trust12-tail-preparation-state-receipt-crosswalk-v1",
        "status": "PREPARED_NOT_CLOSED",
        "sources": [file_reference(path) for path in
                    (STATE_THEORY, CENTRAL_LEDGER, CENTRAL_CLOSURE, KERNEL_SCHEMA, KERNEL_ABI, RECEIPT_SCHEMA)] + [
            file_reference(ROOT / "evidence/runtime-binding-v3" / BINDING[profile] / "bridge-artifacts.json")
            for profile in PROFILE_RUNTIMES],
        "stateFields": state_rows,
        "controlFields": {kind: [name for name in names if name in state_fields] for kind, names in CONTROL_FIELDS.items()},
        "subRecords": sub_records,
        "receipt": {"fields": positional, "events": events,
                    "hashPreimage": "the domain word followed by receipt fields 1 to 16 in kernel schema order"},
        "storageWithoutAbstractField": unmapped,
        "counts": {
            "stateFields": len(state_rows),
            "hookColumnsDerived": sum(1 for row in state_rows for key in DERIVED
                                      if row["runtimes"][key]["status"] == "DERIVED_BY_LAYOUT_IDENTITY"),
            "openStorage": sum(1 for rows in unmapped.values() for row in rows if row["status"] == "OPEN"),
        },
        "openItems": [
            "The formal model reads storage through runtime manifest projections that are locale parameters; no "
            "formal rule reads a slot or a mapping key into an abstract field, and no per-profile manifest instance "
            "exists. This crosswalk is input to such a reader, not a proof of it.",
            "Hook columns are derived by storage layout identity with the Partial runtimes and are not reviewed.",
            "The representation of absent values is not fixed by the model for custody records, for authorities "
            "outside the profile reference and for bindings a profile does not store.",
            "Enum cardinalities differ where the implementation encodes absence as a NONE member: the receipt kind "
            "has two abstract and three concrete values, the record lifecycle three and four.",
            "The model pairs values injectively where the implementation hashes them, for the settlement pair "
            "commitment and the import identifiers.",
            "Profile binding configuration, schema and epoch are not storage fields; they come from the sealed "
            "binding and from constants.",
            "The applied frozen amount of the owned state has no abstract field.",
            "The upstream token storage of the Hook profile is outside these layouts.",
            "The kernel schema describes the verified-full profile as reported by no current implementation, while "
            "the Hook adapter reports that profile identifier and kind.",
        ],
        "nonclaim": NONCLAIM,
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    document = build()
    write_or_check(DOCUMENT, dump_json(document), args.check)
    print(dump_json({"status": "PASS_STATE_RECEIPT_CROSSWALK_" + ("CHECKED" if args.check else "WRITTEN"),
                     "counts": document["counts"]}), end="")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except PreparationError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
