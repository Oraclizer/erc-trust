#!/usr/bin/env python3
"""Seal and verify the frozen inputs of the independent Assurance of the TRUST 1.2 runtime link.

A seal freezes the five identity bundles of the central refinement closure (abstract authority,
normative authority, implementation target, compiled target and product consumer) together with
the runtime-link evidence, the toolchain pins, the reproduction commands and the four
independent checks. Files are addressed by root alias and relative path only, so a seal never
carries a private absolute path. Verification recomputes every selected file set from the same
selectors, so a modified, added or removed file fails the seal.

Two selector forms exist. A path selector names include and exclude patterns under one root;
its first path segment must be literal, so that only that directory is enumerated. A ledger
selector reads an obligation ledger under the evidence root and selects the named files of
every kernel run the ledger cites, so the public specification never has to list internal
evidence directory names.

Usage:
  assurance_seal.py seal   --spec SPEC --root PRODUCT=DIR [--root EVIDENCE=DIR] --output FILE [--status STATUS]
  assurance_seal.py verify --seal SEAL --root PRODUCT=DIR [--root EVIDENCE=DIR]
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

from tail_common import (
    NONCLAIM, OUTPUT, PreparationError, dump_json, load_json, require, require_schema, sha256_file,
    tree_root,
)

SCHEMA = OUTPUT / "assurance-input-seal-schema-v1.json"
SPEC_SCHEMA = "trust12-tail-preparation-assurance-seal-spec-v1"
DRY_RUN = "TEMPLATE_DRY_RUN"
SEALED = "SEALED_FOR_INDEPENDENT_ASSURANCE"
GLOB_CHARACTERS = set("*?[")
EXCLUDED_PARTS = {".git", "node_modules", "__pycache__"}


def parse_roots(values: list[str]) -> dict[str, Path]:
    roots: dict[str, Path] = {}
    for value in values:
        alias, separator, directory = value.partition("=")
        require(separator and alias.replace("_", "").isalpha() and alias.isupper(), f"bad root binding: {value}")
        require(alias not in roots, f"root bound twice: {alias}")
        path = Path(directory).resolve()
        require(path.is_dir(), f"root {alias} is not a directory")
        roots[alias] = path
    return roots


def git(root: Path, *arguments: str) -> str:
    # --no-optional-locks keeps status from refreshing the index of a checkout it only reads.
    completed = subprocess.run(
        ["git", "--no-optional-locks", "-c", f"safe.directory={root.as_posix()}", "-C", str(root), *arguments],
        check=True, capture_output=True, text=True, encoding="utf-8",
    )
    return completed.stdout.strip()


def tracked_files(root: Path) -> list[str]:
    output = subprocess.run(
        ["git", "--no-optional-locks", "-c", f"safe.directory={root.as_posix()}", "-C", str(root), "ls-files", "-z"],
        check=True, capture_output=True,
    ).stdout.decode("utf-8")
    return sorted(path for path in output.split("\0") if path)


def literal_prefix(pattern: str) -> str:
    segments = []
    for segment in pattern.split("/"):
        if GLOB_CHARACTERS.intersection(segment):
            break
        segments.append(segment)
    return "/".join(segments)


def matches(path: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatchcase(path, pattern) for pattern in patterns)


def walked_candidates(root: Path, patterns: list[str]) -> list[str]:
    """Enumerate only the literal prefix of each pattern of a walked (untracked) root."""
    found: set[str] = set()
    for pattern in patterns:
        prefix = literal_prefix(pattern)
        require(prefix and not GLOB_CHARACTERS.intersection(prefix.split("/")[0]),
                f"a walked root needs a literal first segment: {pattern}")
        start = root / prefix
        if start.is_file():
            found.add(prefix)
        elif start.is_dir():
            for path in start.rglob("*"):
                relative_path = path.relative_to(root)
                if path.is_file() and not EXCLUDED_PARTS.intersection(relative_path.parts):
                    found.add(relative_path.as_posix())
    return sorted(found)


def record(root_alias: str, root: Path, path: str) -> dict[str, Any]:
    absolute = root / path
    return {"root": root_alias, "path": path, "bytes": absolute.stat().st_size, "sha256": sha256_file(absolute)}


def ledger_runs(ledger: dict[str, Any]) -> list[tuple[str, str]]:
    runs = set()
    for row in ledger["rows"]:
        for items in row["evidence"].values():
            for item in items:
                if item.get("kind") == "kernel" and item.get("countsTowardClosure") and item.get("root") and item.get("run"):
                    runs.add((item["root"], item["run"]))
    return sorted(runs)


SESSION_DIRECTORY = re.compile(r"-d\s+'([^']+)'")


def session_directories(command: str, evidence_root: Path) -> tuple[list[str], int]:
    """Session directories that a recorded kernel command loads from under the evidence root.

    Directories outside the evidence root are counted, not named: they belong to other roots
    (the product formal tree, a pinned archive dependency, another repository) whose identity
    the seal records through their own bundles or declared toolchain pins.
    """
    inside, outside = set(), 0
    root_text = evidence_root.as_posix().lower()
    for raw in SESSION_DIRECTORY.findall(command):
        path = raw
        if path.startswith("/cygdrive/"):
            drive, rest = path[len("/cygdrive/"):].split("/", 1)
            path = f"{drive.upper()}:/{rest}"
        elif path.startswith("/mnt/") and len(path) > 6 and path[6] == "/":
            path = f"{path[5].upper()}:/{path[7:]}"
        if path.lower().startswith(root_text + "/"):
            inside.add(path[len(root_text) + 1:])
        else:
            outside += 1
    return sorted(inside), outside


def select(selector: dict[str, Any], roots: dict[str, Path], modes: dict[str, str],
           tracked: dict[str, list[str]], owned: set[tuple[str, str]]) -> list[dict[str, Any]]:
    alias = selector["root"]
    require(alias in roots, f"selector names an unbound root: {alias}")
    root = roots[alias]
    if selector.get("remainder"):
        require(modes.get(alias) == "git-tracked", "a remainder selector needs a git-tracked root")
        paths = [path for path in tracked[alias] if (alias, path) not in owned]
    elif "ledger" in selector:
        require(modes.get(alias) == "walk", "a ledger selector needs a walked root")
        ledger_path = root / selector["ledger"]
        require(ledger_path.is_file(), f"ledger missing under {alias}: {selector['ledger']}")
        chosen = set()
        directories = set()
        for run_root, run in ledger_runs(load_json(ledger_path)):
            directories.add(run_root)
            for name in selector["runFiles"]:
                candidate = f"{run_root}/{run}/{name}"
                require((root / candidate).is_file(), f"ledger-cited kernel file missing: {alias}:{candidate}")
                chosen.add(candidate)
            for name in selector.get("optionalRunFiles", []):
                candidate = f"{run_root}/{run}/{name}"
                if (root / candidate).is_file():
                    chosen.add(candidate)
                    if selector.get("followSessionDirectories") and name.endswith(".sh"):
                        inside, _ = session_directories((root / candidate).read_text(encoding="utf-8"), root)
                        directories.update(inside)
        for directory in sorted(directories):
            for pattern in selector.get("rootFiles", []):
                for path in sorted((root / directory).glob(pattern)):
                    if path.is_file():
                        chosen.add(path.relative_to(root).as_posix())
        paths = sorted(chosen)
    else:
        candidates = tracked[alias] if modes.get(alias) == "git-tracked" else walked_candidates(root, selector["include"])
        paths = [path for path in candidates
                 if matches(path, selector["include"]) and not matches(path, selector.get("exclude", []))]
    require(paths or selector.get("allowEmpty", False), f"selector selects nothing under {alias}")
    return [record(alias, root, path) for path in paths]


def root_modes(roots: dict[str, Path], declared: dict[str, str]) -> tuple[dict[str, str], dict[str, list[str]]]:
    require(sorted(declared) == sorted(roots), "the seal specification and the bound roots differ")
    tracked = {}
    for alias, mode in declared.items():
        require(mode in {"git-tracked", "walk"}, f"unknown inventory mode for {alias}: {mode}")
        if mode == "git-tracked":
            tracked[alias] = tracked_files(roots[alias])
    return declared, tracked


def product_state(root: Path) -> dict[str, Any]:
    return {
        "remote": git(root, "remote", "get-url", "origin"),
        "commit": git(root, "rev-parse", "HEAD"),
        "tree": git(root, "rev-parse", "HEAD^{tree}"),
        "cleanWorktree": git(root, "status", "--porcelain") == "",
    }


def collect(bundle: dict[str, Any], roots: dict[str, Path], modes: dict[str, str],
            tracked: dict[str, list[str]], owned: set[tuple[str, str]]) -> list[dict[str, Any]]:
    files: list[dict[str, Any]] = []
    for selector in bundle["selectors"]:
        files += select(selector, roots, modes, tracked, owned)
    files.sort(key=lambda item: (item["root"], item["path"]))
    keys = [(item["root"], item["path"]) for item in files]
    require(len(set(keys)) == len(keys), f"bundle selects a file twice: {bundle['id']}")
    for key in keys:
        require(key not in owned, f"file sealed by two bundles: {key[0]}:{key[1]}")
    owned.update(keys)
    return files


def check_toolchain(toolchain: list[dict[str, Any]], roots: dict[str, Path]) -> None:
    for pin in toolchain:
        location = pin["declaredIn"]
        require(location["root"] in roots, f"toolchain pin names an unbound root: {pin['name']}")
        path = roots[location["root"]] / location["path"]
        require(path.is_file(), f"toolchain declaration file missing: {pin['name']}")
        require(pin["declarationText"] in path.read_text(encoding="utf-8"),
                f"toolchain pin is not declared where the seal says: {pin['name']}")
        require(pin["pin"] in pin["declarationText"], f"declaration text does not carry the pin: {pin['name']}")


def build_seal(spec: dict[str, Any], roots: dict[str, Path], status: str) -> dict[str, Any]:
    require(spec.get("schema") == SPEC_SCHEMA, "wrong seal specification schema")
    require(status in {DRY_RUN, SEALED}, f"unknown seal status: {status}")
    require("PRODUCT" in roots, "the PRODUCT root is mandatory")
    modes, tracked = root_modes(roots, spec["rootInventory"])
    check_toolchain(spec["toolchain"], roots)
    state = product_state(roots["PRODUCT"])
    if status == SEALED:
        require(state["cleanWorktree"], "a seal for Assurance requires a clean product worktree")
    bundles = []
    owned: set[tuple[str, str]] = set()
    for bundle in spec["bundles"]:
        files = collect(bundle, roots, modes, tracked, owned)
        bundles.append({
            "id": bundle["id"],
            "centralClosureRole": bundle["centralClosureRole"],
            "description": bundle["description"],
            "selectors": bundle["selectors"],
            "fileCount": len(files),
            "rootSha256": tree_root(files),
            "files": files,
        })
    return {
        "schema": "trust12-tail-preparation-assurance-input-seal-v1",
        "status": status,
        "rootAliases": sorted(roots),
        "rootInventory": dict(sorted(modes.items())),
        "product": state,
        "bundles": bundles,
        "sealRootSha256": tree_root([item for bundle in bundles for item in bundle["files"]]),
        "toolchain": spec["toolchain"],
        "reproduction": spec["reproduction"],
        "assuranceChecks": spec["assuranceChecks"],
        "reuse": spec["reuse"],
        "exclusions": spec["exclusions"],
        "nonclaim": NONCLAIM,
    }


def verify_seal(seal: dict[str, Any], roots: dict[str, Path]) -> dict[str, Any]:
    require_schema(seal, load_json(SCHEMA), "seal")
    require(sorted(roots) == seal["rootAliases"], "bound roots differ from the sealed root aliases")
    state = product_state(roots["PRODUCT"])
    for key in ("remote", "commit", "tree"):
        require(state[key] == seal["product"][key], f"product {key} drift")
    if seal["status"] == SEALED:
        require(state["cleanWorktree"], "product worktree is dirty")
    modes, tracked = root_modes(roots, seal["rootInventory"])
    check_toolchain(seal["toolchain"], roots)
    problems = []
    owned: set[tuple[str, str]] = set()
    for bundle in seal["bundles"]:
        recorded = {(item["root"], item["path"]): item for item in bundle["files"]}
        try:
            current = collect(bundle, roots, modes, tracked, owned)
        except PreparationError as error:
            problems.append(f"{bundle['id']}: {error}")
            owned.update(recorded)
            continue
        observed = {(item["root"], item["path"]): item for item in current}
        for key in sorted(set(recorded) - set(observed)):
            problems.append(f"{bundle['id']}: sealed file missing: {key[0]}:{key[1]}")
        for key in sorted(set(observed) - set(recorded)):
            problems.append(f"{bundle['id']}: unsealed file present: {key[0]}:{key[1]}")
        for key in sorted(set(recorded) & set(observed)):
            if (recorded[key]["sha256"], recorded[key]["bytes"]) != (observed[key]["sha256"], observed[key]["bytes"]):
                problems.append(f"{bundle['id']}: content drift: {key[0]}:{key[1]}")
        if tree_root(bundle["files"]) != bundle["rootSha256"] or bundle["fileCount"] != len(bundle["files"]):
            problems.append(f"{bundle['id']}: recorded bundle root or count does not match its file list")
    if tree_root([item for bundle in seal["bundles"] for item in bundle["files"]]) != seal["sealRootSha256"]:
        problems.append("recorded seal root does not match the bundles")
    require(not problems, "seal verification failed: " + "; ".join(problems[:20]))
    return {
        "status": "PASS_ASSURANCE_INPUT_SEAL_VERIFIED",
        "sealStatus": seal["status"],
        "bundles": len(seal["bundles"]),
        "files": sum(len(bundle["files"]) for bundle in seal["bundles"]),
        "sealRootSha256": seal["sealRootSha256"],
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    seal_parser = commands.add_parser("seal")
    seal_parser.add_argument("--spec", type=Path, required=True)
    seal_parser.add_argument("--root", action="append", required=True)
    seal_parser.add_argument("--output", type=Path, required=True)
    seal_parser.add_argument("--status", default=DRY_RUN, choices=(DRY_RUN, SEALED))
    verify_parser = commands.add_parser("verify")
    verify_parser.add_argument("--seal", type=Path, required=True)
    verify_parser.add_argument("--root", action="append", required=True)
    args = parser.parse_args(argv)
    roots = parse_roots(args.root)
    if args.command == "seal":
        seal = build_seal(load_json(args.spec), roots, args.status)
        require_schema(seal, load_json(SCHEMA), "seal")
        require(not args.output.exists(), "seal output already exists; seals are never overwritten")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(dump_json(seal), encoding="utf-8", newline="\n")
        print(json.dumps({"status": seal["status"], "bundles": len(seal["bundles"]),
                          "files": sum(bundle["fileCount"] for bundle in seal["bundles"]),
                          "sealRootSha256": seal["sealRootSha256"]}, indent=2))
    else:
        print(json.dumps(verify_seal(load_json(args.seal), roots), indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except (PreparationError, subprocess.CalledProcessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
