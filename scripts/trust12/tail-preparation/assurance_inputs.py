#!/usr/bin/env python3
"""Write and check the input lists of the independent Assurance of the TRUST 1.2 runtime link.

An input list names, by root alias and relative path, with its size and SHA-256, every private file that one
saved-mode recomputation reads, so that the Assurance seal freezes those files through one sealed list file
(see `assurance_seal.py`). Three generators exist:

  index       a private artifact index and every file it names, as a saved-mode verifier opens them;
  directory   every file under a directory whose relative path matches a pattern, such as stored probe receipts;
  reads       the files that a recomputation actually reads: the certificate registry rebuilt in closure mode from
              its locator file, or the call frame report rebuilt from its stage index. The tool runs the same build
              as the saved-mode verifier, requires the rebuild to equal the stored artifact byte for byte, and lists
              the index files, the stored artifacts and the recorded read set. For the registered gate, whose
              verifier rehashes every input file that a recorded kernel run read at its recorded location, it lists
              the index files and every such run input, each named by the most specific bound root that holds it
              and checked against the hash that the run recorded.

`check` regenerates a list from its recorded generator and requires the bytes to be identical, so a file that a
recomputation newly reads, or no longer reads, fails. The tool never runs a prover and never writes into a root.

Usage:
  assurance_inputs.py index     --root ALIAS=DIR [...] --index ALIAS:PATH --base index|root --purpose TEXT --output FILE
  assurance_inputs.py directory --root ALIAS=DIR [...] --directory ALIAS:PATH --pattern GLOB --purpose TEXT
                                --output FILE
  assurance_inputs.py reads     --root PRODUCT=DIR --root EVIDENCE=DIR --recomputation certificate-registry
                                --index EVIDENCE:PATH --purpose TEXT --output FILE
  assurance_inputs.py reads     --root PRODUCT=DIR --root EVIDENCE=DIR --recomputation malformed-call-trace
                                --stage-index EVIDENCE:PATH --index EVIDENCE:PATH --purpose TEXT --output FILE
  assurance_inputs.py reads     --root PRODUCT=DIR --root EVIDENCE=DIR --root MAINTAINER=DIR
                                --recomputation registered-gate --index EVIDENCE:PATH --purpose TEXT --output FILE
  assurance_inputs.py check     --list FILE --root ALIAS=DIR [...]
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import sys
from pathlib import Path, PurePosixPath
from typing import Any

from assurance_seal import LIST_SCHEMA, LIST_SCHEMA_DOCUMENT, parse_roots, record, resolve_inside
from tail_common import PreparationError, dump_json, load_json, require, require_schema, sha256_file, tree_root

TOOL_PATH = "scripts/trust12/tail-preparation/assurance_inputs.py"
NONCLAIM = ("An input list freezes the files that one recomputation reads. It is not a recomputation result, and it "
            "discharges no runtime-link condition and no part of the independent Assurance.")
COLON_SPELLINGS = (":", "")


def location(text: str) -> tuple[str, str]:
    alias, separator, path = text.partition(":")
    require(separator and alias.replace("_", "").isalpha() and alias.isupper() and path,
            f"expected ALIAS:PATH, got {text}")
    return alias, path


def located(roots: dict[str, Path], alias: str, path: str) -> Path:
    require(alias in roots, f"unbound root: {alias}")
    return resolve_inside(roots[alias], path)


def own_identity(roots: dict[str, Path]) -> None:
    """The executing tool is the tool of the bound product tree, so a list records the sealed generator."""
    require("PRODUCT" in roots, "the PRODUCT root is mandatory")
    require(Path(__file__).resolve() == (roots["PRODUCT"] / TOOL_PATH).resolve(),
            "the executing tool is not the tool of the bound product tree")


def on_disk(root: Path, relative: str) -> str:
    """The stored spelling of a recorded relative path. A Linux tool may have written a colon that a Windows host
    stores as U+F03A; both spellings are tried, as the recomputation tools do."""
    candidates = dict.fromkeys((relative, relative.replace(":", ""), relative.replace("", ":")))
    for candidate in candidates:
        if (root / candidate).is_file():
            return candidate
    raise PreparationError(f"recorded read is not a file: {relative}")


def index_files(roots: dict[str, Path], alias: str, path: str, base: str) -> list[tuple[str, str]]:
    index_path = located(roots, alias, path)
    require(index_path.is_file(), f"artifact index missing: {alias}:{path}")
    index = load_json(index_path)
    require(isinstance(index, dict) and index and all(isinstance(value, str) for value in index.values()),
            f"artifact index is not a flat role map: {alias}:{path}")
    parent = PurePosixPath(path).parent
    out = [(alias, path)]
    for role, value in sorted(index.items()):
        relative = (parent / value).as_posix() if base == "index" else value
        require(located(roots, alias, relative).is_file(), f"indexed artifact missing: {role}: {alias}:{relative}")
        out.append((alias, relative))
    return out


def directory_files(roots: dict[str, Path], alias: str, path: str, pattern: str) -> list[tuple[str, str]]:
    directory = located(roots, alias, path)
    require(directory.is_dir(), f"directory missing: {alias}:{path}")
    out = []
    for item in sorted(directory.rglob("*")):
        relative = item.relative_to(directory).as_posix()
        if item.is_file() and "__pycache__" not in item.parts and fnmatch.fnmatchcase(relative, pattern):
            out.append((alias, f"{path.rstrip('/')}/{relative}"))
    require(out, f"no file under {alias}:{path} matches {pattern}")
    return out


def registry_reads(roots: dict[str, Path], index: tuple[str, str]) -> tuple[list[tuple[str, str]], dict[str, Any]]:
    import certificate_registry_v2 as tool

    alias, path = index
    require(alias == "EVIDENCE", "the registry index is an evidence file")
    files = index_files(roots, alias, path, "index")
    named = {role: (PurePosixPath(path).parent / value).as_posix()
             for role, value in load_json(located(roots, alias, path)).items()}
    require(set(named) == {"certificate-registry", "certificate-locators"}, "registry index roles differ")
    locator_path = located(roots, alias, named["certificate-locators"])
    stored = located(roots, alias, named["certificate-registry"]).read_bytes()
    locators = load_json(locator_path)
    reads: set[str] = set()
    rebuilt = tool.build(roots["EVIDENCE"], locators, "closure", tool.locator_identity(locator_path),
                         roots["PRODUCT"], reads)
    require(tool.dump_json(rebuilt).encode("utf-8") == stored,
            "the registry rebuilt in closure mode differs from the stored registry; no list is written")
    files += [("EVIDENCE", on_disk(roots["EVIDENCE"], item)) for item in reads]
    return files, {"ledger": {"root": "EVIDENCE", "path": locators["ledger"]}}


def call_trace_reads(roots: dict[str, Path], index: tuple[str, str],
                     stage_index: tuple[str, str]) -> tuple[list[tuple[str, str]], dict[str, Any]]:
    import malformed_call_trace as tool

    require(index[0] == "EVIDENCE" and stage_index[0] == "EVIDENCE", "the call trace indexes are evidence files")
    files = index_files(roots, *index, "index")
    named = {role: (PurePosixPath(index[1]).parent / value).as_posix()
             for role, value in load_json(located(roots, *index)).items()}
    require(set(named) == {"call-trace-report"}, "call trace index roles differ")
    stored = located(roots, "EVIDENCE", named["call-trace-report"]).read_bytes()
    reads: set[str] = set()
    rebuilt = tool.build(roots["PRODUCT"], roots["EVIDENCE"], located(roots, *stage_index), reads)
    require(tool.dump_json(rebuilt).encode("utf-8") == stored,
            "the call frame report rebuilt from the stage index differs from the stored report; no list is written")
    files += [("EVIDENCE", stage_index[1])]
    files += [("EVIDENCE", on_disk(roots["EVIDENCE"], item)) for item in reads]
    return files, {}


def named_by_root(roots: dict[str, Path], absolute: Path) -> tuple[str, str] | None:
    """The most specific bound root that holds an absolute path, with the path relative to it."""
    best = None
    for alias, root in roots.items():
        base = root.resolve()
        if absolute.is_relative_to(base) and (best is None or len(str(base)) > len(str(roots[best].resolve()))):
            best = alias
    return None if best is None else (best, absolute.relative_to(roots[best].resolve()).as_posix())


def registered_gate_inputs(roots: dict[str, Path], index: tuple[str, str]) -> tuple[list[tuple[str, str]], dict[str, Any]]:
    alias, path = index
    require(alias == "EVIDENCE", "the registered gate index is an evidence file")
    files = index_files(roots, alias, path, "index")
    parent = PurePosixPath(path).parent
    snapshots = [role for role in load_json(located(roots, alias, path)) if role.endswith("-inputs-before")]
    require(snapshots, "the registered gate index names no run input snapshot")
    for role in sorted(snapshots):
        relative = (parent / load_json(located(roots, alias, path))[role]).as_posix()
        rows = json.loads(located(roots, alias, relative).read_text(encoding="utf-8-sig"))
        require(isinstance(rows, list) and rows, f"run input snapshot is empty: {role}")
        for row in rows:
            require(isinstance(row, dict) and set(row) == {"path", "sha256"}, f"run input snapshot row differs: {role}")
            if row["path"] == "<run-local-catalog>":
                continue
            absolute = Path(row["path"]).resolve()
            named = named_by_root(roots, absolute)
            require(named is not None and named[0] != "PRODUCT",
                    f"recorded run input outside every bound evidence root; bind its root: {row['path']}")
            require(absolute.is_file() and sha256_file(absolute) == row["sha256"],
                    f"recorded run input drift: {named[0]}:{named[1]}")
            files.append(named)
    return files, {}


def build_list(roots: dict[str, Path], generator: dict[str, Any], purpose: str) -> dict[str, Any]:
    kind = generator["kind"]
    extra: dict[str, Any] = {}
    if kind == "artifact-index":
        files = index_files(roots, generator["index"]["root"], generator["index"]["path"], generator["indexBase"])
    elif kind == "directory":
        files = directory_files(roots, generator["directory"]["root"], generator["directory"]["path"],
                                generator["pattern"])
    elif kind == "recomputation-reads" and generator["recomputation"] == "certificate-registry":
        files, extra = registry_reads(roots, (generator["index"]["root"], generator["index"]["path"]))
    elif kind == "recomputation-reads" and generator["recomputation"] == "malformed-call-trace":
        files, extra = call_trace_reads(roots, (generator["index"]["root"], generator["index"]["path"]),
                                        (generator["stageIndex"]["root"], generator["stageIndex"]["path"]))
    elif kind == "recomputation-reads" and generator["recomputation"] == "registered-gate":
        files, extra = registered_gate_inputs(roots, (generator["index"]["root"], generator["index"]["path"]))
    else:
        raise PreparationError(f"unknown generator: {kind}")
    records = [record(alias, roots[alias], path) for alias, path in sorted(set(files))]
    document = {
        "schema": LIST_SCHEMA,
        "purpose": purpose,
        "generator": {**generator, **extra},
        "fileCount": len(records),
        "rootSha256": tree_root(records),
        "files": records,
        "nonclaim": NONCLAIM,
    }
    require_schema(document, load_json(LIST_SCHEMA_DOCUMENT), "input list")
    return document


def generator_from(args: argparse.Namespace) -> dict[str, Any]:
    tool = {"root": "PRODUCT", "path": TOOL_PATH}
    if args.command == "index":
        alias, path = location(args.index)
        return {"kind": "artifact-index", "tool": tool, "index": {"root": alias, "path": path}, "indexBase": args.base}
    if args.command == "directory":
        alias, path = location(args.directory)
        return {"kind": "directory", "tool": tool, "directory": {"root": alias, "path": path}, "pattern": args.pattern}
    alias, path = location(args.index)
    generator = {"kind": "recomputation-reads", "tool": tool, "recomputation": args.recomputation,
                 "index": {"root": alias, "path": path}}
    if args.recomputation == "malformed-call-trace":
        require(args.stage_index, "the call trace needs --stage-index")
        stage_alias, stage_path = location(args.stage_index)
        generator["stageIndex"] = {"root": stage_alias, "path": stage_path}
    return generator


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("index", "directory", "reads"):
        sub = commands.add_parser(name)
        sub.add_argument("--root", action="append", required=True)
        sub.add_argument("--purpose", required=True)
        sub.add_argument("--output", type=Path, required=True)
        if name == "index":
            sub.add_argument("--index", required=True)
            sub.add_argument("--base", choices=("index", "root"), required=True)
        elif name == "directory":
            sub.add_argument("--directory", required=True)
            sub.add_argument("--pattern", required=True)
        else:
            sub.add_argument("--recomputation", choices=("certificate-registry", "malformed-call-trace", "registered-gate"),
                             required=True)
            sub.add_argument("--index", required=True)
            sub.add_argument("--stage-index")
    check = commands.add_parser("check")
    check.add_argument("--list", type=Path, required=True)
    check.add_argument("--root", action="append", required=True)
    args = parser.parse_args(argv)
    sys.dont_write_bytecode = True
    roots = parse_roots(args.root)
    own_identity(roots)
    if args.command == "check":
        recorded = args.list.read_bytes()
        document = json.loads(recorded.decode("utf-8"))
        require(document.get("schema") == LIST_SCHEMA, "not an input list")
        generator = {key: value for key, value in document["generator"].items() if key != "ledger"}
        regenerated = dump_json(build_list(roots, generator, document["purpose"])).encode("utf-8")
        require(regenerated == recorded, f"input list differs from its regeneration: {args.list.name}")
        print(json.dumps({"status": "PASS_ASSURANCE_INPUT_LIST_REGENERATED", "files": document["fileCount"],
                          "rootSha256": document["rootSha256"]}, indent=2))
        return 0
    document = build_list(roots, generator_from(args), args.purpose)
    output = args.output.resolve()
    require(not output.exists(), "input list output already exists; lists are never overwritten")
    require(not any(output.is_relative_to(root.resolve()) for alias, root in roots.items() if alias == "PRODUCT"),
            "an input list is private evidence and is never written into the product tree")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(dump_json(document), encoding="utf-8", newline="\n")
    print(json.dumps({"status": "INPUT_LIST_WRITTEN", "files": document["fileCount"],
                      "rootSha256": document["rootSha256"]}, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except (PreparationError, OSError, ValueError, KeyError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
