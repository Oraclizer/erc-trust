#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Read the storage readers of the three profile manifests and compare them with the state and receipt crosswalk.

The formal model abstracts a configuration through a runtime manifest whose projections give each abstract field.
The manifests that the Native cell theorems and the restated Partial and Hook cell theorems of the registered
executions use define their projections by reading storage: the Native manifests read the endpoint storage, and the
reader shared by the two ERC-3643 profiles reads the adapter storage and the upstream token storage. This tool

* extracts, from the Isabelle sources that the kernel sessions stored, the clauses that define those readers: the
  manifest projections, the selector lemmas that state them one field at a time, the struct readers, the helper
  definitions and the profile constants that select a slot;
* derives from the clauses, for every abstract field and every profile, the account, base slot, mapping depth, key,
  word offset and value decoding that the reader uses (a "read form"), interpreting a helper definition only when its
  text equals the text pinned in this file;
* compares the read forms with every column of the crosswalk, in both directions, with the member order of the
  crosswalk sub-records, with the slot tables of the generated bridge and with the layout predicates of the
  manifests;
* with the source texts, also counts the recorded-world reader theorems and the cell theorem statements that name
  the manifests, and with a stored solc build, compares the struct member locations with the compiled layouts.

The comparison is a comparison of definitions. It does not show that a deployed runtime holds the values the reader
gives in a general execution, it does not invert Keccak-256 and it runs no prover or compiler.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import subprocess
import sys

CROSSWALK = "evidence/trust12/runtime-link/tail-preparation/state-receipt-crosswalk-v1.json"
DISPOSITIONS = "evidence/trust12/runtime-link/tail-preparation/reflection-dispositions-v1.json"
FORMAL = {"state": "formal/isabelle/ERC_TRUST/TRUST_Compositional_State.thy",
          "manifest": "formal/isabelle/ERC_TRUST/TRUST_Retrieve_Relation.thy",
          "bridge": "formal/isabelle/ERC_TRUST/TRUST_Runtime_Bridge_Generated.thy"}
OPERATIONS = ("FREEZE", "SEIZE", "CONFISCATE", "LIQUIDATE", "RESTRICT", "RECOVER", "UNFREEZE", "RELEASE",
              "UNRESTRICT")
PROFILES = ("native", "partial", "hook")
RUNTIMES = {"TrustToken": ("native", "endpoint"), "ERC3643TrustAdapter": ("partial", "adapter"),
            "ProfileGovernor": ("partial", "governor"), "ERC3643HookAdapter": ("hook", "adapter"),
            "ERC3643HookGovernor": ("hook", "governor")}
BOUND = ("BOUND_BY_CENTRAL_LEDGER", "DERIVED_BY_LAYOUT_IDENTITY")
WORLDS = tuple(f"w{index:02d}" for index in range(16))
HASH_DOMAINS = ("trust_action_id", "trust_case_id", "trust_hash", "trust_authority_ref")

# Source roles. Each role is one Isabelle theory that a completed kernel session stored.
SOURCE_ROLES = (
    ["shared-reader", "partial-profile", "partial-worlds-0", "hook-profile", "hook-worlds-0"]
    + [f"{profile}-worlds-{index}" for profile in ("partial", "hook") for index in range(1, 5)]
    + [f"{profile}-cell-{operation.lower()}" for profile in ("partial", "hook") for operation in OPERATIONS]
    + ["native-reader", "native-layout", "native-receipts", "native-alias-restrict", "native-alias-remaining",
       "native-cell-freeze-bridge", "native-cell-freeze-post", "native-cell-forward", "native-cell-liquidate",
       "native-cell-restrict", "native-cell-unfreeze", "native-cell-release"])
# The cell theorems of the Native cells: the kernel theories the certificate registry names for each cell.
NATIVE_CELL_THEOREMS = {
    "FREEZE": [("native-cell-freeze-bridge", "b2_native_freeze_cell_enforced"),
               ("native-cell-freeze-post", "qb_native_freeze_cell_enforced")],
    "SEIZE": [("native-cell-forward", "native_seize_certificate_cell_enforced")],
    "CONFISCATE": [("native-cell-forward", "native_confiscate_certificate_cell_enforced")],
    "LIQUIDATE": [("native-cell-liquidate", "lqt_success_alpha_transaction_enforced")],
    "RESTRICT": [("native-cell-restrict", "native_restrict_certificate_cell_enforced")],
    "RECOVER": [("native-cell-forward", "native_recover_certificate_cell_enforced")],
    "UNFREEZE": [("native-cell-unfreeze", "native_unfreeze_certificate_cell_enforced")],
    "RELEASE": [("native-cell-release", "native_release_certificate_cell_enforced")],
    "UNRESTRICT": [("native-cell-restrict", "native_unrestrict_certificate_cell_enforced")],
}
NATIVE_MANIFESTS = ("pw2_manifest keccak", "pw3_manifest keccak lq_pair_certificates", "ru_manifest keccak",
                    "nr_manifest keccak")

# Helper definitions (normalized text) and their meaning. A reader clause is interpreted only through these texts.
PINNED = {
    # Solidity mapping locations: keccak256(abi.encode(key, slot)), keccak256(abi.encode(key2, inner)).
    "pw_mapping_preimage": ("native-reader", "pw_mapping_preimage key slot = pw_pad32 key @ pw_pad32 slot"),
    "pw_nested_preimage": ("native-reader", "pw_nested_preimage key inner_hash = pw_pad32 key @ pw_pad32 inner_hash"),
    "pw_pad32": ("native-reader", "pw_pad32 wv = pw_be 32 wv"),
    # Bits [low, low + width) of a word; a nonzero word is true; a zero word is an absent identifier.
    "pw_bits": ("native-reader", "pw_bits low width wv = (wv div 2 ^ low) mod 2 ^ width"),
    "pw_bool_of": ("native-reader", "pw_bool_of wv <longleftrightarrow> wv <noteq> 0"),
    "pw_option_hash": ("native-reader", "pw_option_hash wv = (if wv = 0 then None else Some wv)"),
    # The endpoint storage of a configuration; a mapping key is read only when the footprint names its preimage.
    "pw_endpoint_storage": ("native-reader", "pw_endpoint_storage cfg = (case current_world cfg (current_endpoint "
                            "cfg) of None <Rightarrow> (<lambda>_. 0) | Some acct <Rightarrow> evm_account_storage "
                            "acct)"),
    "pw_scoped": ("native-reader", "pw_scoped cfg key slot <longleftrightarrow> key < pw_word_bound <and> "
                  "pw_mapping_preimage key slot <in> footprint_mapping_inputs (current_footprint cfg)"),
    "pw_map_read": ("native-reader", "pw_map_read cfg key slot = (if pw_scoped cfg key slot then pw_endpoint_storage "
                    "cfg (keccak (pw_mapping_preimage key slot)) else 0)"),
    "pw_struct_read": ("native-reader", "pw_struct_read cfg key slot reader absent = (if pw_scoped cfg key slot then "
                       "reader (pw_endpoint_storage cfg) (keccak (pw_mapping_preimage key slot)) else absent)"),
    "pw_id_read": ("native-reader", "pw_id_read cfg scope ident slot reader absent = (if ident <in> scope <and> "
                   "ident < pw_word_bound then reader (pw_endpoint_storage cfg) (keccak (pw_mapping_preimage ident "
                   "slot)) else absent)"),
    # Two levels at slot 4 (owner, then spender) and three levels at slot 11 (reference, epoch, nonce).
    "pw_allowance_read": ("native-reader", "pw_allowance_read cfg owner spender = (if pw_scoped cfg owner 4 <and> "
                          "spender < pw_word_bound <and> pw_nested_preimage spender (keccak (pw_mapping_preimage owner "
                          "4)) <in> footprint_mapping_inputs (current_footprint cfg) then pw_endpoint_storage cfg "
                          "(keccak (pw_nested_preimage spender (keccak (pw_mapping_preimage owner 4)))) else 0)"),
    "pw_nonce_key_storage": ("native-reader", "pw_nonce_key_storage cfg nk = pw_endpoint_storage cfg (keccak "
                             "(pw_nested_preimage (snd (snd nk)) (keccak (pw_nested_preimage (fst (snd nk)) (keccak "
                             "(pw_mapping_preimage (fst nk) 11))))))"),
    # The later manifest generations replace the layout predicate, then the receipt projection only.
    "pw2_manifest": ("native-layout", "pw2_manifest keccak = (pw_manifest keccak)<lparr>manifest_layout_matches := "
                     "pw2_layout_matches keccak<rparr>"),
    "pw3_manifest": ("native-receipts", "pw3_manifest keccak certificates = (pw2_manifest keccak)<lparr>"
                     "manifest_receipts := represented_receipts keccak certificates (pw2_manifest keccak)<rparr>"),
    "represented_receipts": ("native-receipts", "represented_receipts keccak certificates manifest cfg command_id = "
                             "(case manifest_receipts manifest cfg command_id of None <Rightarrow> None | Some receipt "
                             "<Rightarrow> translate_receipt keccak certificates command_id receipt)"),
    # A receipt of command kind 3 (LIQUIDATE) is read only with a matching pair certificate; others unchanged.
    "translate_receipt": ("native-receipts", "translate_receipt keccak certificates command_id receipt = (if "
                          "compositional_command_kind receipt = 3 then (case certificates command_id of None "
                          "<Rightarrow> None | Some (settlement, proceeds) <Rightarrow> (if compositional_command_id "
                          "receipt = command_id <and> compositional_external_commitment receipt = keccak (pw_be 32 "
                          "settlement @ pw_be 32 proceeds) then Some (receipt<lparr>compositional_external_commitment "
                          ":= settlement_pair_commitment settlement proceeds<rparr>) else None)) else Some receipt)"),
    "ru_manifest": ("native-alias-restrict", "ru_manifest keccak = pw3_manifest keccak lq_pair_certificates"),
    "nr_manifest": ("native-alias-remaining", "nr_manifest keccak = pw3_manifest keccak lq_pair_certificates"),
    # Shared ERC-3643 reader: mapping location, nonce key hash, balance slot, total supply, receipts, storages.
    "psr_slot": ("shared-reader", "psr_slot keccak key slot = keccak (pw_mapping_preimage key slot)"),
    "psr_nonce_preimage": ("shared-reader", "psr_nonce_preimage domain nk = pw_pad32 domain @ pw_pad32 (fst nk) @ "
                           "pw_pad32 (fst (snd nk)) @ pw_pad32 (snd (snd nk))"),
    "psr_balance_slot": ("shared-reader", "psr_balance_slot kind = (case kind of PSR_Token_Mock <Rightarrow> 4 | "
                         "PSR_Token_TREX <Rightarrow> 102)"),
    "psr_total_supply": ("shared-reader", "psr_total_supply P T = (case psr_token_kind P of PSR_Token_Mock "
                         "<Rightarrow> psr_minted_supply P | PSR_Token_TREX <Rightarrow> T 104)"),
    "psr_read_receipt": ("shared-reader", "psr_read_receipt keccak P A h = (case pw_read_receipt A (psr_slot keccak h "
                         "9) of None <Rightarrow> None | Some receipt <Rightarrow> translate_receipt keccak "
                         "(psr_pair_certificates P) h receipt)"),
    "psr_storage": ("shared-reader", "psr_storage cfg address = (case current_world cfg address of None <Rightarrow> "
                    "(<lambda>_. 0) | Some account <Rightarrow> evm_account_storage account)"),
    "psr_config_state": ("shared-reader", "psr_config_state keccak P cfg = psr_state keccak P (psr_storage cfg "
                         "(psr_adapter P)) (psr_storage cfg (psr_token P))"),
}
# Struct readers and the crosswalk struct types they read.
STRUCT_READERS = {
    "pw_read_effect_head": ("native-reader", ("EffectHead",)),
    "pw_read_effect_link": ("native-reader", ("EffectRecord",)),
    "pw_read_authority": ("native-reader", ("Authority",)),
    "pw_read_binding": ("native-reader", ("Binding",)),
    "pw_read_case": ("native-reader", ("CaseRecord",)),
    "pw_read_action": ("native-reader", ("ActionRecord",)),
    "pw_read_custody": ("native-reader", ("CustodyRecord",)),
    "pw_read_receipt": ("native-reader", ("Receipt",)),
    "psr_read_binding": ("shared-reader", ("DependencyBinding",)),
}
SUBRECORD_READER = {"Receipt": "pw_read_receipt", "ActionRecord": "pw_read_action", "CaseRecord": "pw_read_case"}
SUBRECORD_PUBLIC = {"Receipt": "compositional_receipt", "ActionRecord": "compositional_action_record",
                    "CaseRecord": "compositional_case"}
# Clauses of the reader that a record quotes: (identifier, role, kind, name). Kinds: definition, statement, theorem.
CLAUSES = ([("helper:" + name, role, "definition", name) for name, (role, _) in PINNED.items()]
           + [("struct:" + name, role, "definition", name) for name, (role, _) in STRUCT_READERS.items()]
           + [("shared:psr_state", "shared-reader", "definition", "psr_state"),
              ("shared:psr_state_fields", "shared-reader", "statement", "psr_state_fields"),
              ("shared:psr_manifest", "shared-reader", "definition", "psr_manifest"),
              ("shared:psr_projected", "shared-reader", "theorem", "psr_projected"),
              ("native:pw_manifest", "native-reader", "definition", "pw_manifest"),
              ("native:pw_manifest_selectors", "native-reader", "statement", "pw_manifest_selectors"),
              ("native:pw_layout_slots_agree_with_generated_bridge", "native-reader", "statement",
               "pw_layout_slots_agree_with_generated_bridge"),
              ("native:pw2_mapping_layout", "native-layout", "definition", "pw2_mapping_layout"),
              ("native:pw2_projection_is_the_recorded_projection", "native-layout", "theorem",
               "pw2_projection_is_the_recorded_projection"),
              ("native:pw3_non_receipt_fields_agree", "native-receipts", "theorem", "pw3_non_receipt_fields_agree")]
           + [(f"{profile}:manifest", f"{profile}-profile", "definition", f"psr_{profile}_manifest")
              for profile in ("partial", "hook")]
           + [(f"{profile}:constants", f"{profile}-profile", "statement", f"psr_{profile}_profile_simps")
              for profile in ("partial", "hook")])
CONSTANT_SELECTORS = ("psr_token_kind", "psr_minted_supply")
# Kernel statements that the later Native generations keep every projection of the base manifest, except that the
# third one replaces the receipt projection.
GENERATION_STATEMENTS = {
    "native:pw2_projection_is_the_recorded_projection": [
        "projected_compositional_state (pw2_manifest keccak) cfg = projected_compositional_state (pw_manifest keccak) "
        "cfg"],
    "native:pw3_non_receipt_fields_agree": [
        "(projected_compositional_state (pw3_manifest keccak certificates) cfg) <lparr>compositional_receipts := "
        "compositional_receipts state<rparr> = (projected_compositional_state (pw2_manifest keccak) cfg) <lparr>"
        "compositional_receipts := compositional_receipts state<rparr>"],
}
ESCAPE = re.compile(r"\b(?:sorry|oops)\b")


class SourceError(ValueError):
    """A source text that this tool cannot read as the pinned reader."""


def require(condition, message):
    if not condition:
        raise SourceError(message)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical(value) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True, allow_nan=False).encode("utf-8")


def norm(text: str) -> str:
    """Whitespace collapsed and every Isabelle symbol escape written without its backslash."""
    return re.sub(r"\s+", " ", text.replace("\\<", "<")).strip()


# ----------------------------------------------------------------------------------------------------------------
# Theory text
# ----------------------------------------------------------------------------------------------------------------
class Theory:
    def __init__(self, role: str, text: str):
        self.role, self.text, self.lines = role, text, text.split("\n")
        self._spans = None

    def _quoted(self, start: int) -> tuple[int, str]:
        first = self.text.index('"', start)
        second = self.text.index('"', first + 1)
        body = self.text[first + 1:second]
        require('\\"' not in body, f"{self.role}: escaped quote in a term")
        return first + 1, body

    def definition(self, name: str) -> str:
        hits = list(re.finditer(r"^(?:definition|abbreviation(?: \(input\))?|fun|primrec)\s+" + re.escape(name)
                                + r"\b", self.text, re.M))
        require(len(hits) == 1, f"{self.role}: definition {name} found {len(hits)} times")
        where = re.compile(r"\bwhere\b").search(self.text, hits[0].end())
        require(where is not None, f"{self.role}: definition {name} has no body")
        return norm(self._quoted(where.end())[1])

    def offset(self, name: str, keywords=("lemma", "theorem")) -> int:
        hits = list(re.finditer(r"^(?:" + "|".join(keywords) + r")\s+" + re.escape(name)
                                + r"(?:\s*\[[^\]]*\])?\s*:", self.text, re.M))
        require(len(hits) == 1, f"{self.role}: statement {name} found {len(hits)} times")
        return hits[0].start()

    def statement(self, name: str, keywords=("lemma", "theorem")) -> list[str]:
        start = self.offset(name, keywords)
        position = self.text.index(":", start + len(name)) + 1
        props = []
        while self.text[position:].lstrip().startswith('"'):
            begin, body = self._quoted(position)
            props.append(norm(body))
            position = begin + len(body) + 1
        require(props, f"{self.role}: statement {name} has no proposition")
        return props

    def theorem_statements(self) -> list[tuple[int, list[str]]]:
        result = []
        for match in re.finditer(r"^theorem\s+(\w+)(?:\s*\[[^\]]*\])?\s*:", self.text, re.M):
            result.append((match.start(), self.statement(match.group(1), ("theorem",))))
        return result

    def context_of(self, offset: int) -> tuple[str, ...]:
        """The stack of begin/end block headers active at a text offset."""
        if self._spans is None:
            stack, opened, pending, spans = [], [], None, []
            for number, line in enumerate(self.lines):
                match = re.match(r"^(theory|context|locale|instantiation|class)\b\s*(\S*)", line)
                if match:
                    pending = (match.group(1) + " " + match.group(2)).strip()
                    if re.search(r"\bbegin\s*$", line) and match.group(1) != "theory":
                        stack.append(pending)
                        opened.append(number)
                        pending = None
                    continue
                if re.match(r"^begin\s*$", line):
                    stack.append(pending or "context")
                    opened.append(number)
                    pending = None
                elif re.match(r"^end\s*$", line) and stack:
                    spans.append((opened.pop(), number, tuple(stack)))
                    stack.pop()
            self._spans = spans
        line, best = self.text.count("\n", 0, offset), ()
        for start, end, stack in self._spans:
            if start < line < end and len(stack) > len(best):
                best = stack
        return best


def extract_clauses(sources: dict[str, str]) -> dict[str, object]:
    """The reader clauses of the sources: normalized definition bodies and proposition lists."""
    theories = {role: Theory(role, text) for role, text in sources.items()}
    clauses = {}
    for identifier, role, kind, name in CLAUSES:
        theory = theories[role]
        if kind == "definition":
            clauses[identifier] = theory.definition(name)
        else:
            props = theory.statement(name, ("theorem",) if kind == "theorem" else ("lemma", "theorem"))
            if identifier.endswith(":constants"):
                props = [prop for prop in props if prop.split(" ", 1)[0] in CONSTANT_SELECTORS]
            clauses[identifier] = props
    return clauses


# ----------------------------------------------------------------------------------------------------------------
# Terms
# ----------------------------------------------------------------------------------------------------------------
def closing(text: str, start: int) -> int:
    depth = 0
    for index in range(start, len(text)):
        if text[index] == "(":
            depth += 1
        elif text[index] == ")":
            depth -= 1
            if depth == 0:
                return index
    return -1


def strip_parens(text: str) -> str:
    text = text.strip()
    while text.startswith("(") and closing(text, 0) == len(text) - 1:
        text = text[1:-1].strip()
    return text


def split_top(text: str) -> list[str]:
    parts, depth, current, index = [], 0, [], 0
    while index < len(text):
        for token, step in (("<lparr>", 1), ("<rparr>", -1)):
            if text.startswith(token, index):
                depth += step
                current.append(token)
                index += len(token)
                break
        else:
            char = text[index]
            depth += char in "([{"
            depth -= char in ")]}"
            if char == "," and depth == 0:
                parts.append("".join(current).strip())
                current = []
            else:
                current.append(char)
            index += 1
    parts.append("".join(current).strip())
    return parts


def record_fields(expression: str) -> dict[str, str]:
    expression = expression.strip()
    require(expression.startswith("<lparr>") and expression.endswith("<rparr>"), "not a record: " + expression[:60])
    fields = {}
    for part in split_top(expression[len("<lparr>"):-len("<rparr>")]):
        name, _, value = part.partition(" = ")
        require(value and name.strip() not in fields, "record field: " + part[:60])
        fields[name.strip()] = value.strip()
    return fields


def definition_rhs(body: str, head: str) -> str:
    left, separator, right = body.partition(" = ")
    require(separator and left == head, f"definition head {left!r}, expected {head!r}")
    return right


# ----------------------------------------------------------------------------------------------------------------
# Read forms
# ----------------------------------------------------------------------------------------------------------------
def member_location(expression: str) -> dict:
    e = strip_parens(expression)
    if e == "0":
        return {"stored": False}
    decoders = []
    while True:
        match = re.fullmatch(r"(pw_[a-z_]+_of_code|pw_bool_of|pw_option_hash) (.+)", e)
        if not match:
            break
        decoders.append(match.group(1))
        e = strip_parens(match.group(2))
    bits = [0, 256]
    match = re.fullmatch(r"pw_bits (\d+) (\d+) (.+)", e)
    if match:
        bits = [int(match.group(1)), int(match.group(2))]
        e = strip_parens(match.group(3))
    match = re.fullmatch(r"st base|st \(base \+ (\d+)\)", e)
    require(match is not None, "struct member expression: " + expression)
    return {"stored": True, "word": int(match.group(1) or 0), "bits": bits, "decoders": decoders}


def struct_reader(name: str, body: str) -> dict:
    rhs = strip_parens(definition_rhs(body, f"{name} st base"))
    absent = None
    match = re.fullmatch(r"if (.+) then None else Some (<lparr>.+<rparr>)", rhs)
    if match:
        absent, rhs = match.group(1), match.group(2)
        for clause in absent.split(" <and> "):
            require(re.fullmatch(r"st base = 0|st \(base \+ \d+\) = 0|pw_bits \d+ \d+ \(st base\) = 0", clause.strip()),
                    f"{name}: absent clause {clause}")
    members = {field: member_location(value) for field, value in record_fields(rhs).items()}
    words = sorted({item["word"] for item in members.values() if item["stored"]})
    return {"members": members, "words": words, "width": max(words) + 1 if words else 0, "noneWhen": absent}


def form(kind, **values):
    result = {"kind": kind, "account": None, "layout": None, "slot": None, "key": None, "keyScope": None,
              "word": None, "value": None, "absent": None}
    result.update(values)
    return result


SHARED_PATTERNS = [
    (r"<lambda>(\w+)\. if \1 <in> psr_(\w+) P then (A|T) \(psr_slot keccak \1 (\d+)\) else 0",
     lambda m: form("storage", account=m.group(3), layout="mapping", slot=int(m.group(4)), key="argument",
                    keyScope="psr_" + m.group(2), word=0, value="word", absent="0")),
    (r"<lambda>(\w+)\. if \1 <in> psr_(\w+) P then (A|T) \(psr_slot keccak \1 \(psr_balance_slot \(psr_token_kind "
     r"P\)\)\) else 0",
     lambda m: form("storage", account=m.group(3), layout="mapping", slot="psr_balance_slot", key="argument",
                    keyScope="psr_" + m.group(2), word=0, value="word", absent="0")),
    (r"<lambda>(\w+)\. \1 <in> psr_(\w+) P <and> pw_bool_of \((A|T) \(psr_slot keccak \1 (\d+) \+ (\d+)\)\)",
     lambda m: form("storage", account=m.group(3), layout="mapping", slot=int(m.group(4)), key="argument",
                    keyScope="psr_" + m.group(2), word=int(m.group(5)), value="bool", absent="False")),
    (r"<lambda>(\w+)\. if \1 <in> psr_(\w+) P then (pw_read_\w+) (A|T) \(psr_slot keccak \1 (\d+)\) else (\w+)",
     lambda m: form("storage", account=m.group(4), layout="mapping", slot=int(m.group(5)), key="argument",
                    keyScope="psr_" + m.group(2), value="struct:" + m.group(3), absent=m.group(6))),
    (r"\{(\w+) <in> psr_(\w+) P\. (A|T) \(psr_slot keccak \1 (\d+)\) <noteq> 0\}",
     lambda m: form("storage", account=m.group(3), layout="mapping", slot=int(m.group(4)), key="argument",
                    keyScope="psr_" + m.group(2), word=0, value="bool", absent="not a member")),
    (r"\{(\w+) <in> psr_(\w+) P\. (A|T) \(psr_slot keccak \(keccak \(psr_nonce_preimage \(psr_domain P\) \1\)\) "
     r"(\d+)\) <noteq> 0\}",
     lambda m: form("storage", account=m.group(3), layout="mapping", slot=int(m.group(4)), key="hashOfNonceKey",
                    keyScope="psr_" + m.group(2), word=0, value="bool", absent="not a member")),
    (r"<lambda>(\w+)\. psr_read_binding (A|T) \(psr_slot keccak \(pw_binding_kind_index \1\) (\d+)\)",
     lambda m: form("storage", account=m.group(2), layout="mapping", slot=int(m.group(3)), key="enumIndex",
                    keyScope="every binding kind", value="struct:psr_read_binding", absent="None")),
    (r"(A|T) (\d+)",
     lambda m: form("storage", account=m.group(1), layout="direct", slot=int(m.group(2)), word=0, value="word")),
    (r"pw_bits 0 64 \((A|T) (\d+)\)",
     lambda m: form("storage", account=m.group(1), layout="direct", slot=int(m.group(2)), word=0, value="bits0-64")),
    (r"<lambda>(\w+)\. if \1 <in> psr_(\w+) P then psr_read_receipt keccak P A \1 else None",
     lambda m: form("storage", account="A", layout="mapping", slot=9, key="argument", keyScope="psr_" + m.group(2),
                    value="struct:pw_read_receipt", absent="None", receipts="translated with the pair certificates")),
    (r"<lambda>_ _\. 0", lambda m: form("constant", constant="zero for every owner and spender")),
    (r"<lambda>(\w+)\. if \1 = psr_authority_ref P then Some \(psr_authority P\) else None",
     lambda m: form("constant", constant="the profile authority at the profile authority reference, None elsewhere")),
    (r"psr_total_supply P T", lambda m: form("byTokenKind")),
]
NATIVE_PATTERNS = [
    (r"<lambda>cfg (\w+)\. pw_map_read cfg \1 (\d+)",
     lambda m: form("storage", account="endpoint", layout="mapping", slot=int(m.group(2)), key="argument",
                    keyScope="footprint mapping inputs", word=0, value="word", absent="0")),
    (r"<lambda>cfg (\w+)\. pw_bool_of \(pw_map_read cfg \1 (\d+)\)",
     lambda m: form("storage", account="endpoint", layout="mapping", slot=int(m.group(2)), key="argument",
                    keyScope="footprint mapping inputs", word=0, value="bool", absent="False")),
    (r"<lambda>cfg (\w+)\. pw_struct_read cfg \1 (\d+) (pw_read_\w+) (\w+)",
     lambda m: form("storage", account="endpoint", layout="mapping", slot=int(m.group(2)), key="argument",
                    keyScope="footprint mapping inputs", value="struct:" + m.group(3), absent=m.group(4))),
    (r"<lambda>cfg (\w+)\. pw_id_read cfg \(footprint_(\w+) \(current_footprint cfg\)\) \1 (\d+) (pw_read_\w+) (\w+)",
     lambda m: form("storage", account="endpoint", layout="mapping", slot=int(m.group(3)), key="argument",
                    keyScope="footprint " + m.group(2), value="struct:" + m.group(4), absent=m.group(5))),
    (r"<lambda>cfg\. \{(\w+)\. pw_scoped cfg \1 (\d+) <and> pw_endpoint_storage cfg \(keccak \(pw_mapping_preimage "
     r"\1 \2\)\) <noteq> 0\}",
     lambda m: form("storage", account="endpoint", layout="mapping", slot=int(m.group(2)), key="argument",
                    keyScope="footprint mapping inputs", word=0, value="bool", absent="not a member")),
    (r"<lambda>cfg\. \{nk <in> footprint_nonce_keys \(current_footprint cfg\)\. fst nk < pw_word_bound <and> fst "
     r"\(snd nk\) < pw_word_bound <and> snd \(snd nk\) < pw_word_bound <and> pw_nonce_key_storage cfg nk <noteq> 0\}",
     lambda m: form("storage", account="endpoint", layout="nested3", slot=11, key="components",
                    keyScope="footprint nonce_keys", word=0, value="bool", absent="not a member")),
    (r"pw_allowance_read",
     lambda m: form("storage", account="endpoint", layout="nested2", slot=4, key="components",
                    keyScope="footprint mapping inputs", word=0, value="word", absent="0")),
    (r"<lambda>cfg (\w+)\. pw_read_binding \(pw_endpoint_storage cfg\) \(keccak \(pw_mapping_preimage "
     r"\(pw_binding_kind_index \1\) (\d+)\)\)",
     lambda m: form("storage", account="endpoint", layout="mapping", slot=int(m.group(2)), key="enumIndex",
                    keyScope="every binding kind", value="struct:pw_read_binding", absent="None")),
    (r"<lambda>cfg\. pw_endpoint_storage cfg (\d+)",
     lambda m: form("storage", account="endpoint", layout="direct", slot=int(m.group(1)), word=0, value="word")),
    (r"<lambda>cfg\. pw_bits 0 64 \(pw_endpoint_storage cfg (\d+)\)",
     lambda m: form("storage", account="endpoint", layout="direct", slot=int(m.group(1)), word=0, value="bits0-64")),
]


def read_form(patterns, field: str, expression: str) -> dict:
    e = strip_parens(expression)
    for pattern, build in patterns:
        match = re.fullmatch(pattern, e)
        if match:
            return build(match)
    raise SourceError(f"{field}: unrecognized reader clause {expression}")


def public_members(texts: dict[str, str]) -> dict:
    """Abstract state fields, sub-record member orders, manifest projections and slot tables of the public sources."""
    state = texts["state"]
    match = re.search(r"^record trust_compositional_state =\n((?:  \w+ :: .+\n)+)", state, re.M)
    require(match is not None, "abstract state record missing")
    fields = [line.split("::")[0].strip() for line in match.group(1).splitlines()]
    records = {}
    for name in SUBRECORD_PUBLIC.values():
        match = re.search(r"^record " + name + r" =\n((?:  \w+ :: .+\n)+)", state, re.M)
        require(match is not None, f"record {name} missing")
        records[name] = [line.split("::")[0].strip() for line in match.group(1).splitlines()]
    projected = Theory("manifest", texts["manifest"]).definition("projected_compositional_state")
    projection = {}
    for field, value in record_fields(definition_rhs(projected, "projected_compositional_state manifest "
                                                                 "configuration")).items():
        match = re.fullmatch(r"(manifest_\w+) manifest configuration", value)
        require(match is not None, "projection: " + value)
        projection[field] = match.group(1)
    tables = {}
    bridge = Theory("bridge", texts["bridge"])
    for table in ("native_storage_slots", "profile_adapter_storage_slots", "profile_governor_storage_slots"):
        tables[table] = {label: int(slot) for label, slot in re.findall(r"\(''([\w.]+)'', (\d+)\)",
                                                                       bridge.definition(table))}
    require(list(projection) == fields, "manifest projection order differs from the abstract state")
    return {"stateFields": fields, "subRecords": records, "projection": projection, "tables": tables}


def reader_forms(clauses: dict, public: dict) -> dict:
    """Read forms of every abstract field for the three profiles, derived from the quoted clauses."""
    problems = []
    for name, (_, text) in PINNED.items():
        if clauses.get("helper:" + name) != text:
            problems.append(f"helper {name} differs from the pinned text")
    for identifier, statement in GENERATION_STATEMENTS.items():
        if clauses.get(identifier) != statement:
            problems.append(f"the generation statement {identifier} differs from the pinned statement")
    structs = {name: struct_reader(name, clauses["struct:" + name]) for name in STRUCT_READERS}
    by_manifest = {manifest: field for field, manifest in public["projection"].items()}
    # Native: the base manifest; the later generations replace the layout predicate and the receipt projection.
    native_fields = record_fields(definition_rhs(clauses["native:pw_manifest"], "pw_manifest"))
    selectors = clauses["native:pw_manifest_selectors"]
    native = {}
    for manifest_field, expression in native_fields.items():
        if manifest_field in by_manifest:
            field = by_manifest[manifest_field]
            native[field] = read_form(NATIVE_PATTERNS, field, expression)
            if f"{manifest_field} pw_manifest = {expression}" not in selectors:
                problems.append(f"the Native selector lemma does not state {manifest_field}")
    require(sorted(native) == sorted(public["stateFields"]), "the Native manifest does not project every field")
    native["compositional_receipts"]["receipts"] = "translated with the pair certificates in the third generation"
    # Shared reader for the two adapter profiles.
    shared_fields = record_fields(definition_rhs(clauses["shared:psr_state"], "psr_state keccak P A T"))
    lemma = clauses["shared:psr_state_fields"]
    shared = {}
    for field, expression in shared_fields.items():
        shared[field] = read_form(SHARED_PATTERNS, field, expression)
        if f"{field} (psr_state keccak P A T) = {expression}" not in lemma:
            problems.append(f"the shared selector lemma does not state {field}")
    require(list(shared) == public["stateFields"], "the shared reader does not give every field in order")
    manifest_fields = record_fields(definition_rhs(clauses["shared:psr_manifest"],
                                                   "psr_manifest keccak P expected_code preimages"))
    for manifest_field, field in by_manifest.items():
        if manifest_fields.get(manifest_field) != f"(<lambda>cfg. {field} (psr_config_state keccak P cfg))":
            problems.append(f"the shared manifest does not project {field} through the reader")
    if clauses["shared:psr_projected"] != ["projected_compositional_state (psr_manifest keccak P code preimages) cfg "
                                           "= psr_config_state keccak P cfg"]:
        problems.append("the projection theorem of the shared manifest differs")
    profiles = {"native": native}
    constants = {}
    for profile in ("partial", "hook"):
        expected = (f"psr_{profile}_manifest <equiv> psr_manifest kc psr_{profile}_profile "
                    f"psr_{profile}_expected_code psr_{profile}_preimages")
        if clauses[f"{profile}:manifest"] != expected:
            problems.append(f"the {profile} manifest is not the shared reader manifest")
        values = {}
        for prop in clauses[f"{profile}:constants"]:
            match = re.fullmatch(r"(psr_\w+) psr_" + profile + r"_profile = (\w+)", prop)
            require(match is not None, f"{profile} constant: {prop}")
            values[match.group(1)] = match.group(2)
        require(sorted(values) == sorted(CONSTANT_SELECTORS), f"{profile} constants differ")
        constants[profile] = values
        resolved = {}
        for field, item in shared.items():
            item = dict(item)
            if item["slot"] == "psr_balance_slot":
                item["slot"] = {"PSR_Token_Mock": 4, "PSR_Token_TREX": 102}[values["psr_token_kind"]]
            if item["kind"] == "byTokenKind":
                item = (form("constant", constant="the minted supply of the profile constants")
                        if values["psr_token_kind"] == "PSR_Token_Mock"
                        else form("storage", account="T", layout="direct", slot=104, word=0, value="word"))
            if item["kind"] == "storage":
                item["account"] = {"A": "adapter", "T": "token"}[item["account"]]
            resolved[field] = item
        profiles[profile] = resolved
    layout = {slot: {"depth": int(depth), "width": int(width)} for slot, depth, width in
              re.findall(r"\((\d+), (\d+), (\d+)\)", clauses["native:pw2_mapping_layout"])}
    kernel_slots = {}
    for prop in clauses["native:pw_layout_slots_agree_with_generated_bridge"]:
        match = re.fullmatch(r"map_of native_storage_slots ''([\w.]+)'' = Some (\d+)", prop)
        require(match is not None, "bridge slot statement: " + prop)
        kernel_slots[match.group(1)] = int(match.group(2))
    return {"profiles": profiles, "structs": structs, "constants": constants, "nativeLayout": layout,
            "nativeBridgeSlots": kernel_slots, "problems": problems}


# ----------------------------------------------------------------------------------------------------------------
# Comparison with the crosswalk
# ----------------------------------------------------------------------------------------------------------------
def parse_type(text: str):
    text = text.strip()
    if text.startswith("mapping(") and text.endswith(")"):
        inner, depth = text[len("mapping("):-1], 0
        for index in range(len(inner)):
            depth += inner[index] == "("
            depth -= inner[index] == ")"
            if depth == 0 and inner.startswith(" => ", index):
                return ("mapping", inner[:index].strip(), parse_type(inner[index + 4:]))
        raise SourceError("mapping type: " + text)
    return ("value", text)


def unfold_type(text: str) -> tuple[list[str], str]:
    keys, parsed = [], parse_type(text)
    while parsed[0] == "mapping":
        keys.append(parsed[1])
        parsed = parsed[2]
    return keys, parsed[1]


def domain_of(abstract_type: str) -> str | None:
    match = re.match(r"(\w+) \\<Rightarrow>", abstract_type) or re.fullmatch(r"(\w+) set", abstract_type)
    return match.group(1) if match else None


def disagreement(read: dict, storage: dict, abstract_type: str) -> list[str]:
    reasons = []
    if read["slot"] != storage["slot"]:
        reasons.append(f"slot {read['slot']} read, crosswalk slot {storage['slot']}")
    if storage.get("offset") != 0:
        reasons.append(f"crosswalk byte offset {storage.get('offset')}")
    keys, value = unfold_type(storage["type"])
    depth = {"direct": 0, "mapping": 1, "nested2": 2, "nested3": 3}[read["layout"]]
    if len(keys) != depth:
        reasons.append(f"mapping depth {depth} read, crosswalk type {storage['type']}")
    domain = domain_of(abstract_type)
    if keys:
        if read["key"] == "argument":
            expected = "address" if domain == "trust_address" else "bytes32" if domain in HASH_DOMAINS else None
            if keys[0] != expected:
                reasons.append(f"the key is the {domain} argument, crosswalk key type {keys[0]}")
        elif read["key"] == "enumIndex":
            if not keys[0].startswith("enum ") or domain != "trust_binding_kind":
                reasons.append(f"enumeration index key, crosswalk key type {keys[0]}")
        elif read["key"] == "hashOfNonceKey":
            if keys != ["bytes32"] or domain != "trust_nonce_key":
                reasons.append(f"hashed nonce key, crosswalk key types {keys}")
        elif read["key"] == "components":
            expected = {"nested2": ["address", "address"], "nested3": ["bytes32", "uint64", "uint256"]}[read["layout"]]
            if keys != expected:
                reasons.append(f"component keys, crosswalk key types {keys}")
    if read["value"].startswith("struct:"):
        reader = read["value"].split(":", 1)[1]
        if not value.startswith("struct ") or value.split(".")[-1] not in STRUCT_READERS[reader][1]:
            reasons.append(f"struct reader {reader}, crosswalk value type {value}")
    elif value.startswith("struct "):
        # The only struct read word by word is the owned state of an adapter holder (three words).
        if value.split(".")[-1] != "OwnedState" or read["word"] not in (0, 1, 2):
            reasons.append(f"word {read['word']} of {value}")
    elif value not in {"word": ("uint256", "bytes32"), "bool": ("bool",), "bits0-64": ("uint64",)}.get(read["value"], ()):
        reasons.append(f"{read['value']} read, crosswalk value type {value}")
    return reasons


def comparison(crosswalk: dict, forms: dict, public: dict, layout_words: dict) -> dict:
    rows, mismatches = [], []
    profiles, structs = forms["profiles"], forms["structs"]
    if [entry["abstract"] for entry in crosswalk["stateFields"]] != public["stateFields"]:
        mismatches.append("crosswalk state fields differ from the abstract state")
    for entry in crosswalk["stateFields"]:
        field = entry["abstract"]
        for runtime, column in entry["runtimes"].items():
            profile, role = RUNTIMES[runtime]
            read, status, storage = profiles[profile][field], column["status"], column.get("storage")
            if status in BOUND:
                if read["kind"] == "storage" and read["account"] == role:
                    reasons = disagreement(read, storage, entry["abstractType"])
                    verdict = "AGREES" if not reasons else "MISMATCH"
                else:
                    verdict, reasons = "MISMATCH", [f"crosswalk binds {runtime} storage, the reader reads "
                                                    + (read["account"] or "no storage")]
            elif status == "NO_STORAGE":
                if role == "governor":
                    verdict, reasons = "AGREES_NOT_READ", []
                elif read["kind"] == "constant":
                    verdict, reasons = "AGREES_CONSTANT", []
                elif read["kind"] == "storage" and read["account"] == "token":
                    verdict, reasons = "AGREES_UPSTREAM_TOKEN", []
                else:
                    verdict, reasons = "MISMATCH", [f"crosswalk has no {runtime} storage, the reader reads "
                                                    f"{read['account']} slot {read['slot']}"]
            else:
                verdict, reasons = "MISMATCH", [f"unknown crosswalk status {status}"]
            rows.append({"field": field, "runtime": runtime, "status": status,
                         "slot": storage["slot"] if storage else None, "type": storage["type"] if storage else None,
                         "verdict": verdict})
            mismatches += [f"{field} / {runtime}: {reason}" for reason in reasons]
    reverse = []
    for runtime, (profile, role) in RUNTIMES.items():
        bound, read = {}, {}
        for entry in crosswalk["stateFields"]:
            column = entry["runtimes"][runtime]
            if column["status"] in BOUND:
                bound.setdefault(column["storage"]["slot"], set()).add(entry["abstract"])
        for field, item in profiles[profile].items():
            if item["kind"] == "storage" and item["account"] == role:
                read.setdefault(item["slot"], set()).add(field)
        without = sorted(item["slot"] for item in crosswalk["storageWithoutAbstractField"].get(runtime, []))
        problems = (sorted(set(bound) ^ set(read)) + sorted(set(without) & (set(bound) | set(read)))
                    + sorted(slot for slot in set(bound) & set(read) if bound[slot] != read[slot]))
        reverse.append({"runtime": runtime, "fieldSlots": sorted(bound), "slotsWithoutAbstractField": without,
                        "verdict": "AGREES" if not problems else "MISMATCH"})
        if problems:
            mismatches.append(f"{runtime}: slots read and slots bound differ at {problems}")
    subrecords = []
    for entry in crosswalk["subRecords"]:
        reader = structs[SUBRECORD_READER[entry["kernelStruct"]]]
        members = [item["abstract"] for item in entry["fields"]]
        locations, reasons = [], []
        for member in members:
            location = reader["members"].get(member)
            if not location or not location["stored"]:
                reasons.append(f"{member} is not read")
            else:
                locations.append([location["word"], location["bits"][0]])
        if locations != sorted(locations) or len({tuple(item) for item in locations}) != len(locations):
            reasons.append("member locations do not increase in the crosswalk order")
        if sorted(reader["members"]) != sorted(members):
            reasons.append("the reader and the crosswalk name different members")
        if public["subRecords"][SUBRECORD_PUBLIC[entry["kernelStruct"]]] != members:
            reasons.append("the crosswalk member order differs from the abstract record")
        subrecords.append({"kernelStruct": entry["kernelStruct"], "members": len(members), "locations": locations,
                           "verdict": "AGREES" if not reasons else "MISMATCH"})
        mismatches += [f"sub-record {entry['kernelStruct']}: {reason}" for reason in reasons]
    tables = []
    for entry in crosswalk["stateFields"]:
        for runtime, table in (("TrustToken", "native_storage_slots"),
                               ("ERC3643TrustAdapter", "profile_adapter_storage_slots")):
            storage = entry["runtimes"][runtime].get("storage")
            if storage:
                generated = public["tables"][table].get(storage["projection"])
                kernel = forms["nativeBridgeSlots"].get(storage["projection"]) if runtime == "TrustToken" else generated
                ok = generated == storage["slot"] == kernel
                tables.append({"field": entry["abstract"], "runtime": runtime, "projection": storage["projection"],
                               "slot": storage["slot"], "verdict": "AGREES" if ok else "MISMATCH"})
                if not ok:
                    mismatches.append(f"generated slot table: {storage['projection']} {generated}, crosswalk "
                                      f"{storage['slot']}, kernel statement {kernel}")
    widths = []
    for profile in PROFILES:
        for field, read in profiles[profile].items():
            if read["kind"] != "storage" or read["layout"] == "direct" or read["account"] == "token":
                continue
            reader = read["value"].split(":", 1)[1] if read["value"].startswith("struct:") else None
            if profile == "native":
                table = forms["nativeLayout"].get(str(read["slot"]))
                depth = {"mapping": 1, "nested2": 2, "nested3": 3}[read["layout"]]
                width = structs[reader]["width"] if reader else 1
                ok = table == {"depth": depth, "width": width}
                used = list(range(width))
            else:
                listed = layout_words.get(profile, {}).get(str(read["slot"]))
                used = structs[reader]["words"] if reader else [read["word"]]
                ok = listed is not None and (used == listed if reader else read["word"] in listed)
            widths.append({"profile": profile, "field": field, "slot": read["slot"], "words": used,
                           "verdict": "AGREES" if ok else "MISMATCH"})
            if not ok:
                mismatches.append(f"layout of {profile} {field} at slot {read['slot']} differs from the reader words")
    verdicts = {}
    for row in rows:
        verdicts[row["verdict"]] = verdicts.get(row["verdict"], 0) + 1
    derived = [row for row in rows if row["status"] == "DERIVED_BY_LAYOUT_IDENTITY"]
    return {"rows": rows, "reverse": reverse, "subRecords": subrecords, "generatedTables": tables,
            "layoutWidths": widths, "verdicts": dict(sorted(verdicts.items())),
            "derivedHookColumns": {"total": len(derived),
                                   "agreeing": sum(1 for row in derived if row["verdict"] == "AGREES")},
            "mismatches": mismatches}


def absent_values(forms: dict) -> dict:
    structs, profiles = forms["structs"], forms["profiles"]
    return {"custodyRecords": {"native": {"outsideScope": profiles["native"]["custody_records"]["absent"],
                                          "noneWhen": structs["pw_read_custody"]["noneWhen"]},
                               "adapters": {"outsideScope": profiles["partial"]["custody_records"]["absent"],
                                            "noneWhen": structs["pw_read_custody"]["noneWhen"]}},
            "authorities": {"native": {"outsideScope": profiles["native"]["authorities"]["absent"],
                                       "noneWhen": structs["pw_read_authority"]["noneWhen"]},
                            "adapters": profiles["partial"]["authorities"]["constant"]},
            "bindings": {"native": {"noneWhen": structs["pw_read_binding"]["noneWhen"]},
                         "adapters": {"noneWhen": structs["psr_read_binding"]["noneWhen"],
                                      "notStored": sorted(name for name, item in
                                                          structs["psr_read_binding"]["members"].items()
                                                          if not item["stored"])}}}


# ----------------------------------------------------------------------------------------------------------------
# Source-only facts: layout predicates, recorded worlds, cell statements, member layouts
# ----------------------------------------------------------------------------------------------------------------
def layout_words(sources: dict[str, str]) -> dict:
    result = {}
    for profile in ("partial", "hook"):
        props = Theory(profile, sources[f"{profile}-profile"]).statement(f"psr_{profile}_profile_lists")
        specs = [prop for prop in props if prop.startswith("psr_adapter_specs ")]
        require(len(specs) == 1, f"{profile} adapter specification missing")
        words: dict[str, set] = {}
        for _, slot, offset in re.findall(r"\((\d+), (\d+), (\d+)\)", specs[0]):
            words.setdefault(slot, set()).add(int(offset))
        result[profile] = {slot: sorted(values) for slot, values in sorted(words.items(), key=lambda kv: int(kv[0]))}
    return result


def recorded_worlds(sources: dict[str, str], fields: list[str]) -> dict:
    result, problems = {}, []
    for profile in ("partial", "hook"):
        theories = [Theory(f"{profile}-worlds-{index}", sources[f"{profile}-worlds-{index}"]) for index in range(5)]
        reads = facts = 0
        for world in WORLDS:
            name = f"psr_{profile}_{world}_reads"
            holders = [t for t in theories if re.search(r"^theorem " + name + r":", t.text, re.M)]
            if len(holders) != 1:
                problems.append(f"{name} found in {len(holders)} theories")
                continue
            theory = holders[0]
            storage = (f"(ns_storage_of_entries psr_{profile}_{world}_adapter) "
                       f"(ns_storage_of_entries psr_{profile}_{world}_token)")
            if theory.statement(name, ("theorem",)) != [f"psr_state kc psr_{profile}_profile {storage} = "
                                                         f"psr_{profile}_{world}_state"]:
                problems.append(f"{name} states another equation")
            elif f"context psr_{profile}_keccak" not in theory.context_of(theory.offset(name, ("theorem",))):
                problems.append(f"{name} lies outside the keccak context of the profile")
            else:
                reads += 1
            for field in fields:
                lemma = f"psr_{profile}_{world}_{field}"
                try:
                    props = theory.statement(lemma, ("lemma",))
                except SourceError:
                    problems.append(f"{lemma} missing")
                    continue
                if props == [f"{field} (psr_state kc psr_{profile}_profile {storage}) = {field} "
                             f"psr_{profile}_{world}_state"]:
                    facts += 1
                else:
                    problems.append(f"{lemma} states another equation")
        for theory in theories:
            if ESCAPE.search(theory.text):
                problems.append(f"{theory.role} holds an unfinished proof")
        result[profile] = {"worlds": reads, "fieldFacts": facts}
    return {"profiles": result, "problems": problems}


def cell_statements(sources: dict[str, str]) -> dict:
    result, problems = {"partial": {}, "hook": {}, "native": {}}, []
    for profile in ("partial", "hook"):
        for operation in OPERATIONS:
            theory = Theory(f"{profile}-cell-{operation.lower()}", sources[f"{profile}-cell-{operation.lower()}"])
            names = []
            for offset, props in theory.theorem_statements():
                match = re.match(r"runtime_link_cell_enforced \(<lambda>_\. (\w+)\)", props[0])
                if match:
                    names.append(match.group(1))
                    if f"context psr_{profile}_keccak" not in theory.context_of(offset):
                        problems.append(f"{profile} {operation} cell theorem lies outside the keccak context")
            if names != [f"psr_{profile}_manifest"]:
                problems.append(f"{profile} {operation} cell theorems name {names}")
            if ESCAPE.search(theory.text):
                problems.append(f"{theory.role} holds an unfinished proof")
            result[profile][operation] = names[0] if len(names) == 1 else None
    pattern = re.compile(r"^(?:runtime_link_cell_enforced \(<lambda>_\. ([\w ]+?)\)|alpha_transaction_enforced "
                         r"\(([\w ]+?)\))")
    for operation, items in NATIVE_CELL_THEOREMS.items():
        names = []
        for role, theorem in items:
            theory = Theory(role, sources[role])
            match = pattern.match(theory.statement(theorem, ("theorem",))[0])
            name = (match.group(1) or match.group(2)).strip() if match else None
            if name not in NATIVE_MANIFESTS:
                problems.append(f"Native {operation} theorem {theorem} names {name}")
            if ESCAPE.search(theory.text):
                problems.append(f"{role} holds an unfinished proof")
            names.append({"theorem": theorem, "manifest": name})
        result["native"][operation] = names
    return {"cells": result, "problems": problems}


MEMBER_STRUCTS = {
    "TrustToken": ("implementation/src/TrustToken.sol",
                   [("EffectHead", "pw_read_effect_head"), ("EffectRecord", "pw_read_effect_link"),
                    ("Authority", "pw_read_authority"), ("Binding", "pw_read_binding"), ("CaseRecord", "pw_read_case"),
                    ("ActionRecord", "pw_read_action"), ("CustodyRecord", "pw_read_custody"),
                    ("Receipt", "pw_read_receipt")]),
}
for _contract, _path in (("ERC3643TrustAdapter", "implementation/src/profiles/ERC3643TrustAdapter.sol"),
                         ("ERC3643HookAdapter", "implementation/src/profiles/ERC3643HookAdapter.sol")):
    MEMBER_STRUCTS[_contract] = (_path, [("EffectHead", "pw_read_effect_head"), ("EffectRecord", "pw_read_effect_link"),
                                         ("DependencyBinding", "psr_read_binding"), ("CaseRecord", "pw_read_case"),
                                         ("ActionRecord", "pw_read_action"), ("CustodyRecord", "pw_read_custody"),
                                         ("Receipt", "pw_read_receipt"), ("OwnedState", None)])


def member_layouts(build: dict, forms: dict) -> dict:
    """Struct member locations of the readers against the compiled struct layouts, in declaration order."""
    rows, problems = [], []
    for contract, (path, pairs) in MEMBER_STRUCTS.items():
        layout = build["output"]["contracts"][path][contract]["storageLayout"]
        for struct, reader in pairs:
            keys = [name for name in layout["types"] if name.startswith(f"t_struct({struct})")]
            require(len(keys) == 1, f"{contract} struct {struct} missing")
            compiled = [(member["label"], int(member["slot"]), member["offset"],
                         int(layout["types"][member["type"]]["numberOfBytes"]))
                        for member in layout["types"][keys[0]]["members"]]
            reasons = []
            if reader is None:
                words = {forms["profiles"]["partial"]["frozen_targets"]["word"]: "frozenTarget",
                         forms["profiles"]["partial"]["restriction_flags"]["word"]: "restricted"}
                by_slot = {slot: label for label, slot, _, _ in compiled}
                reasons += [f"word {word} is {by_slot.get(word)}, the reader reads {label}"
                            for word, label in words.items() if by_slot.get(word) != label]
            else:
                stored = [item for item in forms["structs"][reader]["members"].values() if item["stored"]]
                if len(stored) != len(compiled):
                    reasons.append(f"{len(stored)} stored members read, {len(compiled)} compiled")
                shared = {}
                for _, slot, _, _ in compiled:
                    shared[slot] = shared.get(slot, 0) + 1
                for item, (label, slot, offset, size) in zip(stored, compiled):
                    low, width = item["bits"]
                    exact = item["word"] == slot and low == offset * 8 and width == size * 8
                    whole = item["word"] == slot and low == 0 and width == 256 and offset == 0 and shared[slot] == 1
                    if not (exact or whole):
                        reasons.append(f"{label}: word {item['word']} bits {low}+{width}, compiled slot {slot} "
                                       f"offset {offset} size {size}")
            rows.append({"contract": contract, "struct": struct, "members": len(compiled),
                         "verdict": "AGREES" if not reasons else "MISMATCH"})
            problems += [f"{contract}.{struct}: {reason}" for reason in reasons]
    return {"rows": rows, "problems": problems}


# ----------------------------------------------------------------------------------------------------------------
# Saved sources: completed kernel session databases
# ----------------------------------------------------------------------------------------------------------------
def decompress(raw: bytes, decoder: str | None) -> bytes:
    if raw.startswith(b"\xfd7zXZ\x00"):
        import lzma
        return lzma.decompress(raw)
    require(raw.startswith(b"\x28\xb5\x2f\xfd"), "unknown source compression")
    try:
        from compression import zstd  # Python 3.14 and later
        return zstd.decompress(raw)
    except ImportError:
        require(decoder is not None, "a zstd decompressor is required")
        return subprocess.run([decoder, "-d", "-q", "--stdout"], input=raw, check=True, capture_output=True,
                              timeout=120).stdout


def database_sources(path: Path, decoder: str | None = None) -> dict[str, bytes]:
    """The exact sources a completed kernel session database stored, by SHA-256 of their bytes."""
    connection = sqlite3.connect(path.resolve().as_uri() + "?mode=ro&immutable=1", uri=True)
    try:
        info = connection.execute("select return_code, errors, output_heap from isabelle_session_info").fetchall()
        rows = connection.execute("select digest, compressed, body from isabelle_sources").fetchall()
    finally:
        connection.close()
    require(len(info) == 1 and info[0][0] == 0 and info[0][1] is None and bool(info[0][2]),
            "the session database does not record a completed session")
    sources = {}
    for digest, compressed, body in rows:
        raw = bytes(body)
        data = decompress(raw, decoder) if compressed else raw
        require(hashlib.sha1(data).hexdigest() == digest, "a stored source differs from its recorded digest")
        sources[sha256(data)] = data
    return sources


def build_report(sources: dict[str, str], crosswalk: dict, public: dict, build: dict | None) -> dict:
    """Everything a record states, recomputed from the reader sources, the crosswalk and the public sources."""
    clauses = extract_clauses(sources)
    forms = reader_forms(clauses, public)
    words = layout_words(sources)
    compared = comparison(crosswalk, forms, public, words)
    worlds = recorded_worlds(sources, public["stateFields"])
    cells = cell_statements(sources)
    members = member_layouts(build, forms) if build is not None else {"rows": [], "problems": ["no build"]}
    problems = (forms["problems"] + compared["mismatches"] + worlds["problems"] + cells["problems"]
                + members["problems"])
    for role, text in sources.items():
        if ESCAPE.search(text):
            problems.append(f"{role} holds an unfinished proof")
    return {"status": "AGREES" if not problems else "DISAGREES", "clauses": clauses, "forms": forms,
            "layoutWords": words, "comparison": compared, "absentValues": absent_values(forms),
            "recordedWorlds": worlds["profiles"], "cells": cells["cells"], "memberLayouts": members["rows"],
            "problems": problems}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--product-root", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--sources", type=Path, required=True,
                        help="JSON object from source role to a theory file or to {database, sha256}")
    parser.add_argument("--build-info", type=Path)
    parser.add_argument("--zstd")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    root = args.product_root.resolve()
    spec = json.loads(args.sources.read_text(encoding="utf-8"))
    base = args.sources.resolve().parent
    texts = {}
    for role in SOURCE_ROLES:
        item = spec[role]
        if isinstance(item, str):
            texts[role] = (base / item).read_bytes().decode("utf-8")
        else:
            texts[role] = database_sources(base / item["database"], args.zstd)[item["sha256"]].decode("utf-8")
    crosswalk = json.loads((root / CROSSWALK).read_text(encoding="utf-8"))
    public = public_members({name: (root / path).read_text(encoding="utf-8") for name, path in FORMAL.items()})
    build = json.loads(args.build_info.read_text(encoding="utf-8")) if args.build_info else None
    report = build_report(texts, crosswalk, public, build)
    args.out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"status": report["status"], "verdicts": report["comparison"]["verdicts"],
                      "problems": len(report["problems"])}))
    return 0 if report["status"] == "AGREES" else 1


if __name__ == "__main__":
    sys.dont_write_bytecode = True
    raise SystemExit(main())
