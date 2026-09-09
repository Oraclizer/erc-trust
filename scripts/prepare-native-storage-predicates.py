#!/usr/bin/env python3
"""Select exact Native storage-predicate inputs without modifying the proof graph."""
import argparse
import hashlib
import json
from pathlib import Path

NODE_SHA256 = "3944f752467157233871462439e17389366b0873745637600f0cec7284b89bd5"
HOTSPOT_INDICES = (3, 4, 10, 1, 8, 5, 12, 11)


def flatten_concat(term):
    from pyk.kast.inner import KApply
    if isinstance(term, KApply) and term.label.name == "_Map_":
        return flatten_concat(term.args[0]) + flatten_concat(term.args[1])
    return [term]


def account_storage(accounts, address):
    from pyk.kast.inner import KApply
    matches = []
    def visit(term):
        if not isinstance(term, KApply):
            return
        if term.label.name == "<account>" and term.args[0].args[0] == address:
            matches.extend(cell.args[0] for cell in term.args
                           if isinstance(cell, KApply) and cell.label.name == "<storage>")
        for child in term.args:
            visit(child)
    visit(accounts)
    if len(matches) != 1:
        raise ValueError("expected exactly one active-account storage cell")
    return matches[0]


def main():
    from pyk.cterm import CTerm
    from pyk.kast.inner import KApply, KSort, KLabel, KVariable, Subst
    from pyk.kast.manip import free_vars
    from pyk.kast.prelude.ml import mlAnd, mlTop
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--node-json", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--shape", choices=("tail8", "full13", "update13"), default="tail8")
    args = parser.parse_args()
    data = json.loads(args.node_json.read_text(encoding="utf-8"))
    digest = hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()
    if digest != NODE_SHA256:
        raise ValueError("Native node differs from the reviewed symbolic checkpoint")
    cterm = CTerm.from_dict(data)
    if cterm.cell("PC_CELL").token != "19231" or len(cterm.constraints) != 13:
        raise ValueError("unexpected Native program counter or constraints")
    storage = account_storage(cterm.cell("ACCOUNTS_CELL"), cterm.cell("ID_CELL"))
    outer = flatten_concat(storage)
    updates = [term for term in outer if term.label.name == "Map:update"]
    if len(outer) != 34 or len(updates) != 1:
        raise ValueError("unexpected outer storage shape")
    if any(term.label.name != "_|->_" for term in outer if term not in updates):
        raise ValueError("unsupported outer storage expression")
    inner = flatten_concat(updates[0].args[0])
    if len(inner) != 13 or any(term.label.name != "_|->_" for term in inner):
        raise ValueError("unexpected functional-update base")
    selected = [inner[index] for index in HOTSPOT_INDICES]
    hotspot = selected[-1]
    for binding in reversed(selected[:-1]):
        hotspot = KApply("_Map_", binding, hotspot)
    variables = free_vars(hotspot)
    indices = [index for index, term in enumerate(cterm.constraints)
               if free_vars(term) <= variables]
    if variables != {"?WORD"} or indices != [0, 8, 10]:
        raise ValueError("unexpected predicate variable or source conditions")
    gt = KSort("GeneratedTopCell")
    ceil = lambda term: KApply(KLabel("#Ceil", [KSort("Map"), gt]), [term])
    inputs = {"guard.json": mlAnd([cterm.constraints[i] for i in indices], sort=gt),
              "left.json": ceil(hotspot), "right.json": mlTop(sort=gt),
              "duplicate-key-left.json": ceil(KApply("_Map_", selected[0], selected[0]))}
    abstraction = None
    if args.shape != "tail8":
        # The verified node fixes these keys to one base plus offsets 0..12.
        base_key = inner[-1].args[0]
        base_variable = KVariable("STORAGE_BASE", KSort("Int"))
        substitutions = {"STORAGE_BASE": base_key}
        bindings, offsets = [], []
        for index, binding in enumerate(inner):
            key, value = binding.args
            if key == base_key:
                generic_key, offset = base_variable, 0
            elif (isinstance(key, KApply) and key.label.name == "_+Int_"
                  and key.args[0] == base_key):
                generic_key = KApply(key.label, base_variable, key.args[1])
                offset = int(key.args[1].token)
            else:
                raise ValueError("storage key is not the reviewed base plus an offset")
            variable_name = f"STORAGE_VALUE_{index}"
            substitutions[variable_name] = value
            bindings.append(KApply("_|->_", generic_key,
                                   KVariable(variable_name, KSort("Int"))))
            offsets.append(offset)
        if set(offsets) != set(range(13)) or len(set(offsets)) != 13:
            raise ValueError("storage offsets are not exactly 0..12")
        generic_map = bindings[-1]
        for binding in reversed(bindings[:-1]):
            generic_map = KApply("_Map_", binding, generic_map)
        negative_map = KApply("_Map_", bindings[0], bindings[0])
        actual_map = updates[0].args[0]
        if args.shape == "update13":
            update_key = KVariable("UPDATE_KEY", KSort("Int"))
            update_value = KVariable("UPDATE_VALUE", KSort("Int"))
            generic_map = KApply("Map:update", generic_map, update_key, update_value)
            negative_map = KApply("Map:update", negative_map, update_key, update_value)
            substitutions.update(UPDATE_KEY=updates[0].args[1],
                                 UPDATE_VALUE=updates[0].args[2])
            actual_map = updates[0]
        if Subst(substitutions)(generic_map) != actual_map:
            raise ValueError("substitution does not recover the exact original map AST")
        inputs = {"guard.json": mlTop(sort=gt), "left.json": ceil(generic_map),
                  "right.json": mlTop(sort=gt),
                  "duplicate-key-left.json": ceil(negative_map),
                  "actual-left.json": ceil(actual_map)}
        abstraction = {"shape": args.shape, "offsets": offsets,
                       "exactOriginalMapRecovered": True,
                       "selectedExpressionIncludesFunctionalUpdate": args.shape == "update13",
                       "substitution": {key: value.to_dict()
                                        for key, value in substitutions.items()}}
    args.output.mkdir(parents=True, exist_ok=False)
    hashes = {}
    for name, term in inputs.items():
        encoded = (json.dumps(term.to_dict(), indent=2) + "\n").encode()
        (args.output / name).write_bytes(encoded)
        hashes[name] = hashlib.sha256(encoded).hexdigest()
    report = {"schema": "trust-native-predicate-inputs-v1", "sourceCtermSha256": digest,
              "sourceConstraintIndices": indices, "constraintsInSource": 13,
              "hotspotIndices": list(HOTSPOT_INDICES), "guardVariables": sorted(variables),
              "bindingsOutsideUpdateBase": 33, "bindingsInsideUpdateBase": 13,
              "functionalUpdates": 1, "sourceProofModified": False,
              "completeStorageFootprint": False, "files": hashes,
              "nonclaim": "Input selection only; no definedness proof, lookup result, or Native completion."}
    if abstraction is not None:
        substitution = (json.dumps(abstraction.pop("substitution"), indent=2) + "\n").encode()
        (args.output / "substitution.json").write_bytes(substitution)
        hashes["substitution.json"] = hashlib.sha256(substitution).hexdigest()
        report.update(abstraction)
        report.pop("hotspotIndices")
        report["schema"] = "trust-native-offset-predicate-inputs-v1"
        report["sourceConstraintIndices"] = []
        report["guardVariables"] = []
        report["requiredCarrierMode"] = "int-variables"
        report["nonclaim"] = ("Input abstraction and exact substitution only. Totality, "
                              "predicate proof and actual consumption require separate checks.")
    (args.output / "selection.json").write_text(json.dumps(report, indent=2) + "\n",
                                                encoding="utf-8", newline="\n")
    print(json.dumps(report))


if __name__ == "__main__":
    main()