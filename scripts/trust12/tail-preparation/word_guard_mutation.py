#!/usr/bin/env python3
"""Apply one bounded word guard mutant to an isolated copy of the product sources.

The typed entrypoints read their request from calldata as a struct. The source holds no explicit check of the
bounded words: every read of an address, uint64, uint48 or enum field of the calldata struct goes through a decoder
check that the compiler inserts, and a value that does not fit is rejected there with empty revert data. A mutant
therefore cannot delete one source line, as a length guard mutant does. It changes the source so that the decoder
no longer rejects one kind of bounded word:

* a width mutant (address, uint64 or uint48) replaces every read of the fields of that width, in every function
  that takes the request as a calldata struct, by a read of the raw word truncated to the declared width, and
  replaces the one copy of the action request to memory by a field-by-field copy that reads those fields the same
  way; the other fields keep their compiler checks;
* a kind width mutant (the action or the reversal kind word) does the same for the kind field, truncating the raw
  word to eight bits; the explicit conversion of that value to the kind still rejects a value outside the declared
  kinds, so only the width part of the decoder check of the kind word is removed;
* a kind bound mutant declares 256 members for the kind enum, so that the decoder checks only that the kind word
  fits in eight bits; the kernel rules then see a kind outside the declared range.

The rewrite is computed from the source text, the struct layout of the malformed input catalog and the mutant
definition, so the same inputs always give the same bytes. It never edits the product tree: it is applied to the
isolated copy that the word guard probe runner builds.
"""
from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

TYPES_FILE = "implementation/src/generated/IERCTrustKernel.sol"
ENDPOINT_FILES = {
    "Native": "implementation/src/TrustToken.sol",
    "Partial": "implementation/src/profiles/ERC3643TrustAdapter.sol",
    "Hook": "implementation/src/profiles/ERC3643HookAdapter.sol",
}
HELPER_ANCHOR = "    function _requireCalldataLength(uint256 expected) internal pure {\n"
STRUCTS = ("ActionRequest", "ReversalRequest")
WIDTH_TYPES = {"address": "address(uint160({read}))", "uint64": "uint64({read})", "uint48": "uint48({read})",
               "ActionKindWord": "TrustKernelTypes.ActionKind(uint8({read}))",
               "ReversalKindWord": "TrustKernelTypes.ReversalKind(uint8({read}))"}
# A kind width guard names the kind word of one request struct; the catalog lists that word with an enum guard.
KIND_WORD_GUARDS = {"ActionKindWord": "ActionKind", "ReversalKindWord": "ReversalKind"}
ENUM_MEMBERS = 256
ENUM_MEMBER_PREFIX = "WORD_GUARD_MUTANT_KIND_"
PARAMETER = re.compile(r"TrustKernelTypes\.(ActionRequest|ReversalRequest)\s+calldata\s+(\w+)")


class MutationError(RuntimeError):
    """A fail-closed precondition of a bounded word guard mutant did not hold."""


def require(condition: object, message: str) -> None:
    if not condition:
        raise MutationError(message)


def text_sha256(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def code_mask(text: str) -> list[bool]:
    """True for every character of the text that is code, False inside comments and string literals."""
    mask = [True] * len(text)
    index, length = 0, len(text)
    while index < length:
        pair = text[index:index + 2]
        if pair == "//":
            end = text.find("\n", index)
            end = length if end < 0 else end
        elif pair == "/*":
            end = text.find("*/", index + 2)
            require(end >= 0, "unclosed block comment")
            end += 2
        elif text[index] in "\"'":
            quote, end = text[index], index + 1
            while end < length and text[end] != quote:
                end += 2 if text[end] == "\\" else 1
            require(end < length, "unclosed string literal")
            end += 1
        else:
            index += 1
            continue
        for position in range(index, end):
            mask[position] = False
        index = end
    return mask


@dataclass(frozen=True)
class Function:
    name: str
    struct: str
    parameter: str
    body_start: int
    body_end: int


def calldata_request_functions(text: str) -> list[Function]:
    """Every function with a body that takes a request struct as a calldata parameter, with the span of its body."""
    mask = code_mask(text)
    found = []
    for match in re.finditer(r"\bfunction\s+(\w+)\s*\(", text):
        if not mask[match.start()]:
            continue
        depth, index = 1, match.end()
        while depth:
            require(index < len(text), "unbalanced parameter list")
            if mask[index]:
                depth += {"(": 1, ")": -1}.get(text[index], 0)
            index += 1
        parameters = text[match.end():index - 1]
        while index < len(text) and not (mask[index] and text[index] in "{;"):
            index += 1
        require(index < len(text), "function without body or terminator: " + match.group(1))
        if text[index] == ";":
            continue
        start, depth, index = index, 1, index + 1
        while depth:
            require(index < len(text), "unbalanced function body: " + match.group(1))
            if mask[index]:
                depth += {"{": 1, "}": -1}.get(text[index], 0)
            index += 1
        declared = PARAMETER.findall(parameters)
        require(len(declared) <= 1, "a function takes two request structs: " + match.group(1))
        if declared:
            found.append(Function(match.group(1), declared[0][0], declared[0][1], start, index))
    return found


def guard_matches(guard: dict[str, Any] | None, name: str) -> bool:
    """True when a catalog word guard is the bounded word kind that a width or kind width mutant names."""
    if guard is None:
        return False
    if name in KIND_WORD_GUARDS:
        return guard["kind"] == "enum" and guard["enum"] == KIND_WORD_GUARDS[name]
    return guard["kind"] == name


def width_fields(catalog: dict[str, Any], guard: str) -> dict[str, dict[str, int]]:
    """Field name to word index of every bounded word of the given width kind, per request struct."""
    result: dict[str, dict[str, int]] = {}
    for shape in catalog["shapes"].values():
        fields = {item["field"]: int(item["word"]) for item in shape["words"] if guard_matches(item["guard"], guard)}
        result[shape["struct"]] = fields
    require(set(result) == set(STRUCTS), "catalog request structs differ")
    return result


def shape_fields(catalog: dict[str, Any], struct: str) -> list[tuple[str, int]]:
    shape = next(item for item in catalog["shapes"].values() if item["struct"] == struct)
    return [(item["field"], int(item["word"])) for item in shape["words"]]


def helpers(catalog: dict[str, Any], fields: dict[str, dict[str, int]], guard: str, copy_needed: bool) -> str:
    lines = [
        "    // Bounded word guard mutant, isolated copy only: reads one request word without the decoder check of",
        "    // its declared width and truncates it to that width, as a decoder that masks instead of rejecting would.",
    ]
    for struct in STRUCTS:
        lines += [
            f"    function _wordGuardMutantWord(TrustKernelTypes.{struct} calldata request, uint256 index)",
            "        private",
            "        pure",
            "        returns (uint256 word)",
            "    {",
            '        assembly ("memory-safe") {',
            "            word := calldataload(add(request, shl(5, index)))",
            "        }",
            "    }",
            "",
        ]
    if copy_needed:
        lines += [
            "    function _wordGuardMutantCopy(TrustKernelTypes.ActionRequest calldata request)",
            "        private",
            "        pure",
            "        returns (TrustKernelTypes.ActionRequest memory copy)",
            "    {",
        ]
        for field, word in shape_fields(catalog, "ActionRequest"):
            if field in fields["ActionRequest"]:
                read = WIDTH_TYPES[guard].format(read=f"_wordGuardMutantWord(request, {word})")
                lines.append(f"        copy.{field} = {read};")
            else:
                lines.append(f"        copy.{field} = request.{field};")
        lines += ["    }", ""]
    return "\n".join(lines) + "\n"


def truncating_rewrite(text: str, catalog: dict[str, Any], guard: str) -> tuple[str, dict[str, Any]]:
    """Rewrite one endpoint source so that the fields of one width are read truncated instead of checked."""
    require(guard in WIDTH_TYPES, "unknown width kind: " + guard)
    require(text.count(HELPER_ANCHOR) == 1, "helper anchor not found exactly once")
    fields = width_fields(catalog, guard)
    mask = code_mask(text)
    edits: list[tuple[int, int, str]] = []
    reads: dict[str, int] = {}
    copies = 0
    changed: set[str] = set()
    for function in calldata_request_functions(text):
        body = text[function.body_start:function.body_end]
        targets = fields[function.struct]
        if targets:
            pattern = re.compile(r"(?<![\w.])" + re.escape(function.parameter) + r"\.(" + "|".join(sorted(targets))
                                 + r")\b(?!\s*\()")
            for match in pattern.finditer(body):
                start = function.body_start + match.start()
                if not mask[start]:
                    continue
                field = match.group(1)
                read = WIDTH_TYPES[guard].format(read=f"_wordGuardMutantWord({function.parameter}, {targets[field]})")
                edits.append((start, function.body_start + match.end(), read))
                reads[f"{function.struct}.{field}"] = reads.get(f"{function.struct}.{field}", 0) + 1
                changed.add(function.name)
        if function.struct == "ActionRequest" and fields["ActionRequest"]:
            copy = re.compile(r"TrustKernelTypes\.ActionRequest\s+memory\s+\w+\s*=\s*(" + re.escape(function.parameter)
                              + r")\s*;")
            for match in copy.finditer(body):
                start = function.body_start + match.start(1)
                if not mask[start]:
                    continue
                edits.append((start, function.body_start + match.end(1), f"_wordGuardMutantCopy({function.parameter})"))
                copies += 1
                changed.add(function.name)
    require(reads, "the mutant changes no read")
    edits.sort()
    require(all(left[1] <= right[0] for left, right in zip(edits, edits[1:])), "overlapping rewrites")
    result, cursor = [], 0
    for start, end, replacement in edits:
        result.append(text[cursor:start])
        result.append(replacement)
        cursor = end
    result.append(text[cursor:])
    rewritten = "".join(result)
    rewritten = rewritten.replace(HELPER_ANCHOR, helpers(catalog, fields, guard, copies > 0) + HELPER_ANCHOR, 1)
    require(remaining_checked_reads(rewritten, catalog, guard) == 0, "a checked read of a mutated field remains")
    return rewritten, {"reads": dict(sorted(reads.items())), "memoryCopies": copies, "functions": sorted(changed)}


def remaining_checked_reads(text: str, catalog: dict[str, Any], guard: str) -> int:
    """Reads of the mutated fields that still go through the decoder check in a function that takes the request as
    a calldata struct: field reads, and whole copies of the action request to memory, which check every field."""
    fields = width_fields(catalog, guard)
    mask = code_mask(text)
    count = 0
    for function in calldata_request_functions(text):
        targets = fields[function.struct]
        if not targets:
            continue
        body = text[function.body_start:function.body_end]
        pattern = re.compile(r"(?<![\w.])" + re.escape(function.parameter) + r"\.(" + "|".join(sorted(targets))
                             + r")\b(?!\s*\()")
        count += sum(1 for match in pattern.finditer(body) if mask[function.body_start + match.start()])
        if function.struct == "ActionRequest":
            copy = re.compile(r"TrustKernelTypes\.ActionRequest\s+memory\s+\w+\s*=\s*" + re.escape(function.parameter)
                              + r"\s*;")
            count += sum(1 for match in copy.finditer(body) if mask[function.body_start + match.start()])
    return count


def widen_enum(text: str, enum: str) -> tuple[str, dict[str, Any]]:
    """Declare 256 members for one kind enum by appending members after the last declared one."""
    pattern = re.compile(r"(    enum " + re.escape(enum) + r" \{\n)((?:        \w+,\n)*        \w+\n)(    \})")
    matches = list(pattern.finditer(text))
    require(len(matches) == 1, "kind enum not found exactly once: " + enum)
    match = matches[0]
    declared = re.findall(r"\w+", match.group(2))
    require(0 < len(declared) < ENUM_MEMBERS and not any(name.startswith(ENUM_MEMBER_PREFIX) for name in declared),
            "kind enum already widened: " + enum)
    added = [f"{ENUM_MEMBER_PREFIX}{value}" for value in range(len(declared), ENUM_MEMBERS)]
    members = ",\n".join("        " + name for name in declared + added) + "\n"
    rewritten = text[:match.start(2)] + members + text[match.end(2):]
    return rewritten, {"enum": enum, "declaredMembers": len(declared), "membersAfter": ENUM_MEMBERS}


MUTANT_KEYS = {
    "truncate-width": {"id", "kind", "guard", "profiles", "fault", "expectedVerdict", "repinAdapterCreationHash"},
    "widen-enum": {"id", "kind", "enum", "fault", "expectedVerdict", "repinAdapterCreationHash"},
}
EQUIVALENT_KEYS = {"equivalentFailure", "rationale", "subsumingRule"}
ENUMS = ("ActionKind", "ReversalKind")


def validate_mutant_list(product: Path, document: dict[str, Any]) -> list[dict[str, Any]]:
    """The declared mutants, checked against their contract and, for an equivalent mutant, against the sources
    that hold the rule which subsumes the weakened check."""
    require(document.get("schema") == "trust12-malformed-word-guard-mutants-v1", "mutant list schema drift")
    mutants = document["mutants"]
    require(isinstance(mutants, list) and mutants, "no declared mutant")
    require(len({row["id"] for row in mutants}) == len(mutants), "mutant identifiers repeat")
    for row in mutants:
        kind = row.get("kind")
        require(kind in MUTANT_KEYS, "unknown mutant kind: " + str(kind))
        keys = MUTANT_KEYS[kind] | (EQUIVALENT_KEYS if row.get("expectedVerdict") == "EQUIVALENT" else set())
        require(set(row) == keys, "mutant keys differ: " + row["id"])
        require(row["expectedVerdict"] in ("DETECTED", "EQUIVALENT") and isinstance(row["fault"], str) and row["fault"],
                "mutant verdict or fault differs: " + row["id"])
        if kind == "truncate-width":
            require(row["guard"] in WIDTH_TYPES and row["profiles"]
                    and len(set(row["profiles"])) == len(row["profiles"])
                    and set(row["profiles"]) <= set(ENDPOINT_FILES), "width mutant differs: " + row["id"])
            require(row["repinAdapterCreationHash"] is ("Hook" in row["profiles"]), "factory pin step differs: " + row["id"])
        else:
            require(row["enum"] in ENUMS and row["repinAdapterCreationHash"] is True, "kind mutant differs: " + row["id"])
        if row["expectedVerdict"] == "EQUIVALENT":
            failure = row["equivalentFailure"]
            require(set(failure) == {"error", "reason"} and isinstance(failure["error"], str)
                    and type(failure["reason"]) is int and isinstance(row["rationale"], str) and row["rationale"],
                    "equivalent mutant failure differs: " + row["id"])
            require(isinstance(row["subsumingRule"], list) and row["subsumingRule"], "no subsuming rule: " + row["id"])
            for anchor in row["subsumingRule"]:
                require(set(anchor) == {"file", "snippet"} and anchor["file"].startswith("implementation/src/"),
                        "subsuming rule anchor differs: " + row["id"])
                text = (product / anchor["file"]).read_text(encoding="utf-8")
                require(text.count(anchor["snippet"]) == 1, "subsuming rule is not in the current source: " + anchor["file"])
    return mutants


def apply(workdir: Path, mutant: dict[str, Any], catalog: dict[str, Any]) -> dict[str, Any]:
    """Apply one declared mutant to the isolated copy and return the record of every changed file."""
    files = []
    if mutant["kind"] == "truncate-width":
        targets = [(ENDPOINT_FILES[profile], profile) for profile in mutant["profiles"]]
        for relative, profile in targets:
            path = workdir / relative
            before = path.read_text(encoding="utf-8")
            after, detail = truncating_rewrite(before, catalog, mutant["guard"])
            path.write_text(after, encoding="utf-8", newline="\n")
            files.append({"file": relative, "profile": profile, "beforeSha256": text_sha256(before),
                          "afterSha256": text_sha256(after), **detail})
    elif mutant["kind"] == "widen-enum":
        path = workdir / TYPES_FILE
        before = path.read_text(encoding="utf-8")
        after, detail = widen_enum(before, mutant["enum"])
        path.write_text(after, encoding="utf-8", newline="\n")
        files.append({"file": TYPES_FILE, "profile": None, "beforeSha256": text_sha256(before),
                      "afterSha256": text_sha256(after), **detail})
    else:
        raise MutationError("unknown mutant kind: " + str(mutant.get("kind")))
    return {"files": files}


def expected_rewrite(product: Path, mutant: dict[str, Any], catalog: dict[str, Any]) -> dict[str, Any]:
    """The record that applying the mutant to the current product sources gives, without writing anything."""
    files = []
    if mutant["kind"] == "truncate-width":
        for profile in mutant["profiles"]:
            relative = ENDPOINT_FILES[profile]
            before = (product / relative).read_text(encoding="utf-8")
            after, detail = truncating_rewrite(before, catalog, mutant["guard"])
            files.append({"file": relative, "profile": profile, "beforeSha256": text_sha256(before),
                          "afterSha256": text_sha256(after), **detail})
    elif mutant["kind"] == "widen-enum":
        before = (product / TYPES_FILE).read_text(encoding="utf-8")
        after, detail = widen_enum(before, mutant["enum"])
        files.append({"file": TYPES_FILE, "profile": None, "beforeSha256": text_sha256(before),
                      "afterSha256": text_sha256(after), **detail})
    else:
        raise MutationError("unknown mutant kind: " + str(mutant.get("kind")))
    return {"files": files}
