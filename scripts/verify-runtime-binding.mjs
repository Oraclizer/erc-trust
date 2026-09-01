import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { keccak256 } from "../sdk/node_modules/ethers/lib.esm/index.js";
import { resolvePinnedSolc } from "./lib/resolve-pinned-solc.mjs";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const evidenceRoot = join(repositoryRoot, "evidence", "end-to-end-refinement", "runtime-binding-current-v2");
const manifestPath = join(evidenceRoot, "manifest.json");
const qualificationReceiptPath = join(
  repositoryRoot,
  "evidence",
  "end-to-end-refinement",
  "runtime-binding-current-profile-qualification-v3.json",
);
const manifestBytes = readFileSync(manifestPath);
const manifest = JSON.parse(manifestBytes.toString("utf8"));
const lock = JSON.parse(readFileSync(join(repositoryRoot, "formal", "kevm", "dependencies.lock.json"), "utf8"));
const pinnedSolc = resolvePinnedSolc(lock.components.solc);
const semanticCheckNames = [
  "abi",
  "storageLayout",
  "creationBytecode",
  "runtimeTemplate",
  "methodIdentifiers",
  "immutableReferences",
];

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function stable(value) {
  if (Array.isArray(value)) return value.map(stable);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]));
  }
  return value;
}

function same(left, right) {
  return JSON.stringify(stable(left)) === JSON.stringify(stable(right));
}

function abiSame(left, right) {
  const normalize = (value) => value.map(stable).sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b)));
  return JSON.stringify(normalize(left)) === JSON.stringify(normalize(right));
}

function semanticStorageLayout(layout) {
  const memo = new Map();
  const expand = (typeId) => {
    if (memo.has(typeId)) return memo.get(typeId);
    const source = layout.types[typeId];
    if (!source) throw new Error(`unknown layout type: ${typeId}`);
    const target = { encoding: source.encoding, label: source.label, numberOfBytes: source.numberOfBytes };
    memo.set(typeId, target);
    if (source.key) target.key = expand(source.key);
    if (source.value) target.value = expand(source.value);
    if (source.base) target.base = expand(source.base);
    if (source.members) {
      target.members = source.members.map((member) => ({
        contract: member.contract,
        label: member.label,
        offset: member.offset,
        slot: member.slot,
        type: expand(member.type),
      }));
    }
    return target;
  };
  return layout.storage.map((item) => ({
    contract: item.contract,
    label: item.label,
    offset: item.offset,
    slot: item.slot,
    type: expand(item.type),
  }));
}

function immutablePositions(value) {
  return Object.values(value ?? {}).flat().map(({ start, length }) => ({ start, length }))
    .sort((left, right) => left.start - right.start || left.length - right.length);
}

function semanticChecks(artifact, compiler) {
  return {
    abi: abiSame(artifact.abi, compiler.abi),
    storageLayout: same(
      semanticStorageLayout(artifact.storageLayout),
      semanticStorageLayout(compiler.storageLayout),
    ),
    creationBytecode:
      normalizeHex(artifact.bytecode.object) === normalizeHex(compiler.evm.bytecode.object),
    runtimeTemplate:
      normalizeHex(artifact.deployedBytecode.object) === normalizeHex(compiler.evm.deployedBytecode.object),
    methodIdentifiers: same(artifact.methodIdentifiers, compiler.evm.methodIdentifiers),
    immutableReferences: same(
      immutablePositions(artifact.deployedBytecode.immutableReferences),
      immutablePositions(compiler.evm.deployedBytecode.immutableReferences),
    ),
  };
}

function classifyRuntimeBinding({
  authoritativeExpectedArtifactSha256,
  candidateExpectedArtifactSha256,
  actualArtifactSha256,
  checks,
}) {
  if (candidateExpectedArtifactSha256 !== authoritativeExpectedArtifactSha256) {
    return {
      status: "FAIL_EXPECTED_ARTIFACT_HASH_OVERWRITE",
      pass: false,
      failedSemanticChecks: [],
    };
  }
  const failedSemanticChecks = semanticCheckNames.filter((name) => checks[name] !== true);
  if (failedSemanticChecks.length !== 0) {
    return { status: "FAIL_RUNTIME_SEMANTIC_MISMATCH", pass: false, failedSemanticChecks };
  }
  return {
    status: actualArtifactSha256 === candidateExpectedArtifactSha256
      ? "PASS_RUNTIME_BINDING_EXACT"
      : "PASS_RUNTIME_PAYLOAD_EXACT_WITH_PACKAGING_DRIFT",
    pass: true,
    failedSemanticChecks,
  };
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function mutateHex(value) {
  const prefix = value.startsWith("0x") ? "0x" : "";
  const hex = value.slice(prefix.length);
  if (hex.length === 0) throw new Error("cannot mutate empty hex");
  const last = hex.at(-1).toLowerCase() === "0" ? "1" : "0";
  return `${prefix}${hex.slice(0, -1)}${last}`;
}

function semanticMutant(artifact, semanticClass) {
  const mutant = clone(artifact);
  if (semanticClass === "abi") {
    mutant.abi.push({
      inputs: [],
      name: "__runtimeBindingMutant",
      outputs: [],
      stateMutability: "view",
      type: "function",
    });
  } else if (semanticClass === "storageLayout") {
    const type = Object.keys(mutant.storageLayout.types)[0] ?? "t_runtime_binding_mutant";
    if (!mutant.storageLayout.types[type]) {
      mutant.storageLayout.types[type] = {
        encoding: "inplace",
        label: "uint256",
        numberOfBytes: "32",
      };
    }
    mutant.storageLayout.storage.push({
      astId: -1,
      contract: "__RuntimeBindingMutant",
      label: "__runtimeBindingMutant",
      offset: 0,
      slot: "340282366920938463463374607431768211455",
      type,
    });
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

function absolute(repoPath) {
  return join(repositoryRoot, ...repoPath.split("/"));
}

function normalizeHex(value) {
  const hex = value.startsWith("0x") ? value.slice(2) : value;
  if (!/^[0-9a-fA-F]*$/.test(hex) || hex.length % 2 !== 0) throw new Error("invalid hex");
  return hex.toLowerCase();
}

function keccak(hex) {
  const output = keccak256(`0x${normalizeHex(hex)}`);
  if (!/^0x[0-9a-f]{64}$/.test(output)) throw new Error(`bad Keccak output: ${output}`);
  return output;
}

function runPinnedSolc(inputText) {
  const command = pinnedSolc.execution === "wsl" ? "wsl.exe" : pinnedSolc.binaryPath;
  const args = pinnedSolc.execution === "wsl"
    ? ["-d", pinnedSolc.distribution, "-e", pinnedSolc.binaryPath, "--standard-json"]
    : ["--standard-json"];
  const outputText = execFileSync(command, args, {
      input: inputText,
      encoding: "utf8",
      maxBuffer: 512 * 1024 * 1024,
    });
  const output = JSON.parse(outputText);
  const errors = (output.errors ?? []).filter((entry) => entry.severity === "error");
  if (errors.length !== 0) throw new Error(`solc replay error: ${errors[0].formattedMessage}`);
  return { outputText, output };
}

if (manifest.schemaVersion !== 3 || manifest.kind !== "ERC_TRUST_PUBLIC_RUNTIME_BINDING_MANIFEST_V2") {
  throw new Error(`unsupported public runtime-binding manifest: ${manifest.schemaVersion}`);
}
const rootEntries = [];
const checked = [];
const subjectResults = [];
const sourceIdentities = [];

for (const bundle of manifest.bundles) {
  for (const file of bundle.files) {
    const bytes = readFileSync(absolute(file.path));
    if (bytes.length !== file.bytes || statSync(absolute(file.path)).size !== file.bytes) {
      throw new Error(`size mismatch: ${file.path}`);
    }
    if (sha256(bytes) !== file.sha256) throw new Error(`hash mismatch: ${file.path}`);
    rootEntries.push(`${file.path}\0${file.sha256}\n`);
  }

  const bundleFile = (name) => {
    const file = bundle.files.find((candidate) => candidate.path.endsWith(`/${name}`));
    if (!file) throw new Error(`bundle file missing: ${bundle.id}/${name}`);
    return absolute(file.path);
  };
  const inputPath = bundleFile("standard-json-input.json");
  const outputPath = bundleFile("standard-json-output.json");
  const bridgePath = bundleFile("bridge-artifacts.json");
  const identitiesPath = bundleFile("source-identities.json");
  const inputText = readFileSync(inputPath, "utf8");
  const storedOutputText = readFileSync(outputPath, "utf8");
  const input = JSON.parse(inputText);
  const storedOutput = JSON.parse(storedOutputText);
  const bridge = JSON.parse(readFileSync(bridgePath, "utf8"));
  const identities = JSON.parse(readFileSync(identitiesPath, "utf8"));

  if (Object.keys(input.sources).length !== bundle.sourceCount || identities.length !== bundle.sourceCount) {
    throw new Error(`source count mismatch: ${bundle.id}`);
  }
  for (const identity of identities) {
    const source = input.sources[identity.path]?.content;
    if (typeof source !== "string") throw new Error(`source missing from input: ${identity.path}`);
    const sourceBytes = Buffer.from(source, "utf8");
    if (sourceBytes.length !== identity.bytes || sha256(sourceBytes) !== identity.sha256) {
      throw new Error(`input source identity mismatch: ${identity.path}`);
    }
    const workingSha256 = sha256(readFileSync(absolute(identity.path)));
    if (workingSha256 !== identity.sha256) {
      throw new Error(`working source drift: ${identity.path}: ${workingSha256} != ${identity.sha256}`);
    }
    sourceIdentities.push({ bundle: bundle.id, ...identity });
  }

  const replay = runPinnedSolc(inputText);
  if (sha256(Buffer.from(replay.outputText, "utf8")) !== sha256(Buffer.from(storedOutputText, "utf8"))) {
    throw new Error(`raw compiler output mismatch: ${bundle.id}`);
  }
  if (!same(replay.output, storedOutput)) throw new Error(`parsed compiler output mismatch: ${bundle.id}`);
  if (bridge.length !== bundle.subjectCount) throw new Error(`subject count mismatch: ${bundle.id}`);

  for (const subject of bridge) {
    const compiler = replay.output.contracts?.[subject.source]?.[subject.contract];
    if (!compiler) throw new Error(`compiler subject missing: ${subject.id}`);
    if (!same(compiler.abi, subject.abi)) throw new Error(`ABI mismatch: ${subject.id}`);
    if (!same(compiler.storageLayout, subject.storageLayout)) throw new Error(`layout mismatch: ${subject.id}`);
    if (!same(compiler.evm.methodIdentifiers, subject.methodIdentifiers)) {
      throw new Error(`method identifier mismatch: ${subject.id}`);
    }
    const runtime = normalizeHex(compiler.evm.deployedBytecode.object);
    const creation = normalizeHex(compiler.evm.bytecode.object);
    const runtimeBytes = Buffer.from(runtime, "hex");
    const creationBytes = Buffer.from(creation, "hex");
    if (
      runtimeBytes.length !== subject.runtimeTemplate.byteLength
      || sha256(runtimeBytes) !== subject.runtimeTemplate.sha256
      || keccak(runtime) !== subject.runtimeTemplate.keccak256
    ) throw new Error(`runtime identity mismatch: ${subject.id}`);
    if (
      creationBytes.length !== subject.creationBytecode.byteLength
      || sha256(creationBytes) !== subject.creationBytecode.sha256
      || keccak(creation) !== subject.creationBytecode.keccak256
    ) throw new Error(`creation identity mismatch: ${subject.id}`);

    const artifactBytes = readFileSync(absolute(subject.foundryCrossCheck.artifactPath));
    const artifact = JSON.parse(artifactBytes.toString("utf8"));
    const currentArtifactSha256 = sha256(artifactBytes);
    const historicalArtifactSha256 = subject.foundryCrossCheck.artifactSha256;
    const checks = semanticChecks(artifact, compiler);
    if (!same(checks, subject.foundryCrossCheck.checks) || Object.values(checks).some((value) => !value)) {
      throw new Error(`Foundry cross-check mismatch: ${subject.id}`);
    }
    const disposition = classifyRuntimeBinding({
      authoritativeExpectedArtifactSha256: historicalArtifactSha256,
      candidateExpectedArtifactSha256: historicalArtifactSha256,
      actualArtifactSha256: currentArtifactSha256,
      checks,
    });
    if (!disposition.pass) throw new Error(`${disposition.status}: ${subject.id}`);

    const historicalExactPath = classifyRuntimeBinding({
      authoritativeExpectedArtifactSha256: historicalArtifactSha256,
      candidateExpectedArtifactSha256: historicalArtifactSha256,
      actualArtifactSha256: historicalArtifactSha256,
      checks,
    });
    if (historicalExactPath.status !== "PASS_RUNTIME_BINDING_EXACT") {
      throw new Error(`historical exact classification path failed: ${subject.id}`);
    }

    const hostileSemanticMutations = semanticCheckNames.map((semanticClass) => {
      const mutantChecks = semanticChecks(semanticMutant(artifact, semanticClass), compiler);
      const mutantDisposition = classifyRuntimeBinding({
        authoritativeExpectedArtifactSha256: historicalArtifactSha256,
        candidateExpectedArtifactSha256: historicalArtifactSha256,
        actualArtifactSha256: currentArtifactSha256,
        checks: mutantChecks,
      });
      const killed = mutantChecks[semanticClass] === false
        && mutantDisposition.status === "FAIL_RUNTIME_SEMANTIC_MISMATCH";
      if (!killed) throw new Error(`semantic mutation survived (${semanticClass}): ${subject.id}`);
      return {
        class: semanticClass,
        status: "KILLED",
        failedSemanticChecks: mutantDisposition.failedSemanticChecks,
      };
    });

    const packagingMutant = { ...clone(artifact), __runtimeBindingPackagingMutation: true };
    const packagingMutantBytes = Buffer.from(`${JSON.stringify(packagingMutant, null, 2)}\n`, "utf8");
    const packagingMutantChecks = semanticChecks(packagingMutant, compiler);
    const packagingOnlyMutation = classifyRuntimeBinding({
      authoritativeExpectedArtifactSha256: historicalArtifactSha256,
      candidateExpectedArtifactSha256: historicalArtifactSha256,
      actualArtifactSha256: sha256(packagingMutantBytes),
      checks: packagingMutantChecks,
    });
    if (
      sha256(packagingMutantBytes) === currentArtifactSha256
      || packagingOnlyMutation.status !== "PASS_RUNTIME_PAYLOAD_EXACT_WITH_PACKAGING_DRIFT"
    ) throw new Error(`packaging-only mutation misclassified: ${subject.id}`);

    const overwrittenExpectedArtifactSha256 = currentArtifactSha256 === historicalArtifactSha256
      ? `${historicalArtifactSha256.slice(0, -1)}${historicalArtifactSha256.at(-1) === "0" ? "1" : "0"}`
      : currentArtifactSha256;
    const expectedHashOverwriteMutation = classifyRuntimeBinding({
      authoritativeExpectedArtifactSha256: historicalArtifactSha256,
      candidateExpectedArtifactSha256: overwrittenExpectedArtifactSha256,
      actualArtifactSha256: currentArtifactSha256,
      checks,
    });
    if (expectedHashOverwriteMutation.status !== "FAIL_EXPECTED_ARTIFACT_HASH_OVERWRITE") {
      throw new Error(`expected-hash overwrite mutation survived: ${subject.id}`);
    }

    subjectResults.push({
      id: subject.id,
      bundle: bundle.id,
      artifactPath: subject.foundryCrossCheck.artifactPath,
      historicalArtifactSha256,
      currentArtifactSha256,
      historicalArtifactExact: currentArtifactSha256 === historicalArtifactSha256,
      semanticChecks: checks,
      disposition: disposition.status,
      hostileSemanticMutations,
      packagingOnlyMutation: {
        status: packagingOnlyMutation.status,
        currentArtifactSha256,
        mutatedArtifactSha256: sha256(packagingMutantBytes),
      },
      expectedHashOverwriteMutation: {
        status: expectedHashOverwriteMutation.status,
        authoritativeExpectedArtifactSha256: historicalArtifactSha256,
        overwrittenCandidateSha256: overwrittenExpectedArtifactSha256,
      },
      historicalExactClassifierPath: historicalExactPath.status,
    });
  }
  checked.push({ id: bundle.id, sources: bundle.sourceCount, subjects: bundle.subjectCount });
}

const deterministicRoot = sha256(Buffer.from(rootEntries.join(""), "utf8"));
if (deterministicRoot !== manifest.deterministicRootSha256) throw new Error("deterministic root mismatch");

const resolvedFixturePath =
  "evidence/end-to-end-refinement/runtime-binding-current-v2/resolved/fixture-pure-v1.json";
const resolvedFixtureBytes = readFileSync(absolute(resolvedFixturePath));
const resolvedFixture = JSON.parse(resolvedFixtureBytes.toString("utf8"));
const nativeDeployment = resolvedFixture.deployments.find((deployment) => deployment.label === "TrustToken");
if (!nativeDeployment) throw new Error("Native resolved runtime deployment missing");
const nativeRuntime = nativeDeployment.runtime;
const nativeResolvedHex = normalizeHex(readFileSync(absolute(nativeRuntime.path), "utf8").trim());
const nativeResolvedBytes = Buffer.from(nativeResolvedHex, "hex");
if (
  nativeResolvedBytes.length !== nativeRuntime.byteLength
  || sha256(nativeResolvedBytes) !== nativeRuntime.sha256
) throw new Error("Native resolved runtime identity drift");

const semanticMutationCases = subjectResults.flatMap((subject) => subject.hostileSemanticMutations);
const stableSubjects = subjectResults.map((subject) => ({
  id: subject.id,
  bundle: subject.bundle,
  artifactPath: subject.artifactPath,
  authoritativeArtifactSha256: subject.historicalArtifactSha256,
  semanticChecks: subject.semanticChecks,
  semanticPayloadPass: Object.values(subject.semanticChecks).every((value) => value === true),
  hostileSemanticMutations: subject.hostileSemanticMutations,
  packagingOnlyMutationStatus: subject.packagingOnlyMutation.status,
  expectedHashOverwriteMutationStatus: subject.expectedHashOverwriteMutation.status,
  historicalExactClassifierPath: subject.historicalExactClassifierPath,
}));
const qualificationReceipt = {
  schemaVersion: 3,
  kind: "ERC_TRUST_RUNTIME_BINDING_CURRENT_PROFILE_QUALIFICATION_V3",
  status: "PASS_RUNTIME_SEMANTIC_IDENTITY",
  date: "2026-09-01",
  manifest: {
    path: "evidence/end-to-end-refinement/runtime-binding-current-v2/manifest.json",
    sha256: sha256(manifestBytes),
    deterministicRootSha256: deterministicRoot,
  },
  compiler: {
    ...manifest.compiler,
    dependencyLockPath: "formal/kevm/dependencies.lock.json",
    dependencyLockSha256: sha256(readFileSync(absolute("formal/kevm/dependencies.lock.json"))),
  },
  sourceIdentities,
  nativeResolvedRuntime: {
    resolvedFixturePath,
    resolvedFixtureSha256: sha256(resolvedFixtureBytes),
    hexPath: nativeRuntime.path,
    hexArtifactSha256: sha256(readFileSync(absolute(nativeRuntime.path))),
    runtimeBytes: nativeRuntime.byteLength,
    runtimeBytesSha256: nativeRuntime.sha256,
  },
  subjects: stableSubjects,
  verifierMutationValidation: {
    historicalExactClassifierPaths: {
      passed: subjectResults.filter((subject) => subject.historicalExactClassifierPath === "PASS_RUNTIME_BINDING_EXACT").length,
      required: subjectResults.length,
      status: "PASS",
    },
    semanticMutations: {
      classes: semanticCheckNames,
      killed: semanticMutationCases.filter((mutation) => mutation.status === "KILLED").length,
      required: subjectResults.length * semanticCheckNames.length,
      status: "PASS",
    },
    packagingOnlyMutations: {
      driftPass: subjectResults.filter((subject) =>
        subject.packagingOnlyMutation.status === "PASS_RUNTIME_PAYLOAD_EXACT_WITH_PACKAGING_DRIFT").length,
      required: subjectResults.length,
      status: "PASS",
    },
    expectedHashOverwriteMutations: {
      failedClosed: subjectResults.filter((subject) =>
        subject.expectedHashOverwriteMutation.status === "FAIL_EXPECTED_ARTIFACT_HASH_OVERWRITE").length,
      required: subjectResults.length,
      status: "PASS",
    },
  },
  qualification: {
    expectedArtifactHashesOverwritten: false,
    pinnedCompilerReplayPass: true,
    rawCompilerOutputExact: true,
    sourceIdentityPass: true,
    sixSemanticChecksPerSubjectPass: true,
    currentProfileConsumerRows: ["ACT-01", "Core49", "Supporting24"],
    supportingQualifiedDelta: 0,
    coreRefinementQualifiedDelta: 0,
    cSeriesReceiptDelta: 0,
    centralCredit: 0,
  },
  checkedBundles: checked,
  nonclaims: [
    "The authoritative whole-file Foundry artifact identity is retained while transient observed packaging hashes remain outside this stable receipt.",
    "Packaging-drift PASS establishes equality only for the six enumerated semantic projections against pinned-solc output.",
    "This receipt does not prove compiler correctness, constructor or deployment execution, deployed-address identity, live topology, external policy truth, or legal truth.",
    "This receipt identifies the repaired candidate runtime but does not by itself grant C0-C6 or row qualification credit.",
  ],
};

const receiptText = `${JSON.stringify(qualificationReceipt, null, 2)}\n`;
const args = new Set(process.argv.slice(2));
if (args.has("--write-receipt")) writeFileSync(qualificationReceiptPath, receiptText, "utf8");
if (args.has("--check-receipt")) {
  if (!existsSync(qualificationReceiptPath)) throw new Error("runtime-binding qualification receipt missing");
  if (readFileSync(qualificationReceiptPath, "utf8") !== receiptText) {
    throw new Error("runtime-binding qualification receipt drift");
  }
}
const output = {
  status: qualificationReceipt.status,
  deterministicRootSha256: deterministicRoot,
  checked,
  subjects: subjectResults.length,
  semanticMutationsKilled: qualificationReceipt.verifierMutationValidation.semanticMutations.killed,
  semanticMutationsRequired: qualificationReceipt.verifierMutationValidation.semanticMutations.required,
  packagingOnlyDriftPass: qualificationReceipt.verifierMutationValidation.packagingOnlyMutations.driftPass,
  expectedHashOverwriteFailedClosed:
    qualificationReceipt.verifierMutationValidation.expectedHashOverwriteMutations.failedClosed,
  expectedArtifactHashesOverwritten: false,
};
if (args.has("--write-receipt") || args.has("--check-receipt")) {
  output.receiptPath = "evidence/end-to-end-refinement/runtime-binding-current-profile-qualification-v3.json";
  output.receiptSha256 = sha256(Buffer.from(receiptText, "utf8"));
}
console.log(JSON.stringify(output, null, 2));
