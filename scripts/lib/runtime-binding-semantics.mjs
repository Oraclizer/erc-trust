// SPDX-License-Identifier: BSD-3-Clause
//
// Semantic projections of a compiled contract shared by the runtime binding generator and
// verifier: the six checks that compare a Foundry artifact with a pinned-compiler output
// (ABI, storage layout without AST node identifiers, creation bytecode, runtime template,
// method identifiers, immutable references).

export const semanticCheckNames = ["abi", "storageLayout", "creationBytecode", "runtimeTemplate", "methodIdentifiers", "immutableReferences"];

// The standard JSON equivalent of foundry.toml. The generator writes it into every stored
// compiler input and the verifier requires every stored input to carry exactly this object.
export const pinnedCompilerSettings = {
  optimizer: { enabled: true, runs: 1 },
  metadata: { useLiteralContent: false, bytecodeHash: "none", appendCBOR: false },
  outputSelection: {
    "*": {
      "*": [
        "abi",
        "evm.bytecode.object",
        "evm.bytecode.linkReferences",
        "evm.deployedBytecode.object",
        "evm.deployedBytecode.linkReferences",
        "evm.deployedBytecode.immutableReferences",
        "evm.methodIdentifiers",
        "storageLayout",
      ],
    },
  },
  evmVersion: "cancun",
  viaIR: true,
  libraries: {},
};

export function stable(value) {
  if (Array.isArray(value)) return value.map(stable);
  if (value !== null && typeof value === "object") return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]));
  return value;
}

export function normalizeHex(value) {
  const hex = value.startsWith("0x") ? value.slice(2) : value;
  if (!/^[0-9a-fA-F]*$/.test(hex) || hex.length % 2 !== 0) throw new Error("invalid bytecode hex");
  return hex.toLowerCase();
}

export function semanticStorageLayout(layout) {
  const memo = new Map();
  const expand = (typeId) => {
    if (memo.has(typeId)) return memo.get(typeId);
    const source = layout.types[typeId];
    if (!source) throw new Error(`unknown storage-layout type: ${typeId}`);
    const target = { encoding: source.encoding, label: source.label, numberOfBytes: source.numberOfBytes };
    memo.set(typeId, target);
    if (source.key) target.key = expand(source.key);
    if (source.value) target.value = expand(source.value);
    if (source.base) target.base = expand(source.base);
    if (source.members) {
      target.members = source.members.map((member) => ({ contract: member.contract, label: member.label, offset: member.offset, slot: member.slot, type: expand(member.type) }));
    }
    return target;
  };
  return layout.storage.map((item) => ({ contract: item.contract, label: item.label, offset: item.offset, slot: item.slot, type: expand(item.type) }));
}

export const normalizedAbi = (value) => value.map(stable).sort((left, right) => JSON.stringify(left).localeCompare(JSON.stringify(right)));

export const immutablePositions = (value) => Object.values(value ?? {}).flat().map(({ start, length }) => ({ start, length })).sort((left, right) => left.start - right.start || left.length - right.length);

// `compiler` is a contract object of a standard JSON output ({abi, storageLayout, evm: {...}});
// `artifact` is a Foundry artifact ({abi, storageLayout, bytecode, deployedBytecode, methodIdentifiers}).
export function semanticChecks(artifact, compiler) {
  return {
    abi: JSON.stringify(normalizedAbi(artifact.abi)) === JSON.stringify(normalizedAbi(compiler.abi)),
    storageLayout: JSON.stringify(stable(semanticStorageLayout(artifact.storageLayout))) === JSON.stringify(stable(semanticStorageLayout(compiler.storageLayout))),
    creationBytecode: normalizeHex(artifact.bytecode.object) === normalizeHex(compiler.evm.bytecode.object),
    runtimeTemplate: normalizeHex(artifact.deployedBytecode.object) === normalizeHex(compiler.evm.deployedBytecode.object),
    methodIdentifiers: JSON.stringify(stable(artifact.methodIdentifiers)) === JSON.stringify(stable(compiler.evm.methodIdentifiers)),
    immutableReferences: JSON.stringify(immutablePositions(artifact.deployedBytecode.immutableReferences)) === JSON.stringify(immutablePositions(compiler.evm.deployedBytecode.immutableReferences)),
  };
}

// A Foundry artifact rendered as a compiler-output contract, so that stored bridge artifacts
// (ABI, semantic storage layout, method identifiers, hashes) can be compared with the same code.
export function artifactAsCompilerContract(artifact) {
  return {
    abi: artifact.abi,
    storageLayout: artifact.storageLayout,
    evm: {
      bytecode: { object: artifact.bytecode.object },
      deployedBytecode: { object: artifact.deployedBytecode.object, immutableReferences: artifact.deployedBytecode.immutableReferences ?? {} },
      methodIdentifiers: artifact.methodIdentifiers,
    },
  };
}

// Deliberate semantic mutants of a Foundry artifact, one per class; the verifier proves that
// each of them fails exactly its own semantic check.
function mutateHex(value) {
  const prefix = value.startsWith("0x") ? "0x" : "";
  const hex = value.slice(prefix.length);
  if (hex.length === 0) throw new Error("cannot mutate empty hex");
  const last = hex.at(-1).toLowerCase() === "0" ? "1" : "0";
  return `${prefix}${hex.slice(0, -1)}${last}`;
}
export function semanticMutant(artifact, semanticClass) {
  const mutant = JSON.parse(JSON.stringify(artifact));
  if (semanticClass === "abi") {
    mutant.abi.push({ inputs: [], name: "__runtimeBindingMutant", outputs: [], stateMutability: "view", type: "function" });
  } else if (semanticClass === "storageLayout") {
    const type = Object.keys(mutant.storageLayout.types)[0] ?? "t_runtime_binding_mutant";
    if (!mutant.storageLayout.types[type]) mutant.storageLayout.types[type] = { encoding: "inplace", label: "uint256", numberOfBytes: "32" };
    mutant.storageLayout.storage.push({ astId: -1, contract: "__RuntimeBindingMutant", label: "__runtimeBindingMutant", offset: 0, slot: "340282366920938463463374607431768211455", type });
  } else if (semanticClass === "creationBytecode") {
    mutant.bytecode.object = mutateHex(mutant.bytecode.object);
  } else if (semanticClass === "runtimeTemplate") {
    mutant.deployedBytecode.object = mutateHex(mutant.deployedBytecode.object);
  } else if (semanticClass === "methodIdentifiers") {
    mutant.methodIdentifiers["__runtimeBindingMutant()"] = "ffffffff";
  } else if (semanticClass === "immutableReferences") {
    mutant.deployedBytecode.immutableReferences ??= {};
    mutant.deployedBytecode.immutableReferences.__runtimeBindingMutant = [{ start: 0, length: 1 }];
  } else {
    throw new Error(`unknown semantic mutation class: ${semanticClass}`);
  }
  return mutant;
}
