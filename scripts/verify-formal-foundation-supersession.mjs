// SPDX-License-Identifier: BSD-3-Clause

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import {
  copyFileSync,
  cpSync,
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifestPath = resolve(
  repositoryRoot,
  "evidence/public-release/formal-foundation-supersession-v1.json",
);
const lockPath = resolve(repositoryRoot, "formal-dependencies-public-v1.lock.json");
const historicalCommit = "3f3e15964969d2646e9240d273e8270987e1c59e";
const historicalTree = "dedde2ed94611dcfc53e6b1d4dd264c5acb522d0";
const currentCommit = "db8e0802e55f0229cf7bc9e5e6cfbf40681adbba";
const currentTree = "98535a359438140178b98551bd02d51c5230e623";

const mappings = [
  ["Canton_Bridge.thy", "cf479648b750ce9ca677a179a1f923bfb9af58a7", "d7f385e9480d7df16c81dc707fd7ba22d23fc41b7b040b21c9e30d1d94fc3dc2"],
  ["Composition.thy", "8abce6825acd4c0be4e739cacaaeeb5d649cb368", "9dd217120df981957c32de0a71bf283cb5248dcde254952e00ee82c4627669a1"],
  ["DQuencer_Instance.thy", "5b6e514f54e483670a03227cdfeba52b0473e1e8", "6d0647966aaf2ff41d0090d4883e829277879a094ebab6702ca6985195622dbd"],
  ["External_Instance.thy", "b92e300ecfcfb10cbdfbb02d3a085cdc1bdc9520", "b9a2086736db22ff93367c911c387d28609c76ed137d5526ec0ebef7db47ad68"],
  ["Functor_Laws.thy", "b3faf59afa4f88f29451d25cc6c30de92311785b", "f79fa0111ba88fe48c54b6113dd21233f4d58c5e98fc858151523f2b993beb11"],
  ["Hierarchy.thy", "3663865823ae70c8aff95c4a566374c3d4b837d6", "b28c6260bd010c203d48328c908f000205d9eda99088a01f2a33667b81d87ba8"],
  ["Priority_Resolution.thy", "e20c60b3a6fb4506225aab3786e689660edc9093", "0e83ca9855254e583a8aead5233ce27d1b216a92bbe36d42276f77ea2e5fb98f"],
  ["Proof_Automation.thy", "313207826e6a0bed98587ff5629028864d7907ca", "4e2bb6e82d9399ef1e8de59f5c67414d484b3484b92026f37b88354f60c6322d"],
  ["Regulatory_Instance.thy", "d4cc06563db428306391e8f6dd3de691d8ae2315", "94a057046f7e2cfae605eb2f32bd9cfb65cbf050300769171c5ff33c8669c3b6"],
  ["State_Preservation.thy", "5f36ea0fecb3b4e1a23d37688f1646404cbc8778", "bf52fd23b8c7a9225a6e14e3b32a0de6ec9d211be0c8a7ecaacc6bd317ad0865"],
].map(([name, blob, digest]) => ({
  historicalPath: `Cross_Domain_State_Preservation/${name}`,
  historicalBlob: blob,
  historicalSha256: digest,
  current: [{
    path: `Cross_Domain_State_Preservation/${name}`,
    blob,
    sha256: digest,
  }],
  disposition: name.endsWith(".thy") ? "BYTE_EXACT_THEORY" : "BYTE_EXACT_DOCUMENT_INPUT",
}));

mappings.splice(10, 0,
  {
    historicalPath: "Cross_Domain_State_Preservation/ROOT",
    historicalBlob: "6c3183f76788faa5fda4171b024c9eb659c3e845",
    historicalSha256: "ce6d2b0131e449a6d4df23b5cde34b089958a3d59f8512b42b51da23cdadab36",
    current: [
      {
        path: "Cross_Domain_State_Preservation/ROOT",
        blob: "518f30ad7c201cb8590172b33d4c4d15b9e46482",
        sha256: "c9acb92791fc5624b21008ae1ea3412cbb514d6b0568d5455fb49bb009cbbe50",
      },
      {
        path: "Regulatory_Action_Composition/ROOT",
        blob: "9ac5878ce0ece963a5fffa0d396e13ec59a6529a",
        sha256: "ecfdba9c69492160bff760718c5a8c1f0259df40c5754ff18d04d2af2fb01f94",
      },
    ],
    disposition: "SESSION_PACKAGING_SPLIT",
  },
);

mappings.splice(11, 0,
  {
    historicalPath: "Cross_Domain_State_Preservation/document/root.bib",
    historicalBlob: "aa2a5a252b056baa2ef6806ce0978435c4fcda74",
    historicalSha256: "2823e8fff9dfa970d12b7efdd8ff3e88296dc5d62b2aaff3ece6d5a35430d10d",
    current: [{
      path: "Cross_Domain_State_Preservation/document/root.bib",
      blob: "aa2a5a252b056baa2ef6806ce0978435c4fcda74",
      sha256: "2823e8fff9dfa970d12b7efdd8ff3e88296dc5d62b2aaff3ece6d5a35430d10d",
    }],
    disposition: "BYTE_EXACT_DOCUMENT_INPUT",
  },
);

mappings.splice(12, 0,
  {
    historicalPath: "Cross_Domain_State_Preservation/document/root.tex",
    historicalBlob: "05d284a3e77d083cff2e3b80380a09187f78317a",
    historicalSha256: "575f96078aad26b55cfacca1daf7717c0cd337f32223385782809a1ee02e7083",
    current: [
      {
        path: "Cross_Domain_State_Preservation/document/root.tex",
        blob: "bf39b2aad15cc2c0e63c52802aba583561f9ebfa",
        sha256: "7dd178be2bdee8364d2a02a0757f0564c6eee0ba4ff469d570babc950744f68e",
      },
      {
        path: "Regulatory_Action_Composition/document/root.tex",
        blob: "b316ad24a5882217df7d35a355eeb0bf6d42892e",
        sha256: "b22c3a24bbf44764ad23105934cf6e3c3e0d6d8a9a23e970f26f2e532181d1f3",
      },
    ],
    disposition: "NON_PROOF_DOCUMENTATION_SPLIT",
  },
  {
    historicalPath: "Cross_Domain_State_Preservation/Regulatory_Action_Composition.thy",
    historicalBlob: "a64c73cb8c0bbc6d261ededa90e23080c97b99f4",
    historicalSha256: "cdbc4c8af4d34b1aa37064cb5a9520e6e67a61f7ccbe0ba0159f0f2f29dd7e69",
    current: [{
      path: "Regulatory_Action_Composition/Regulatory_Action_Composition.thy",
      blob: "f6fbb773963d8ae7ea6fb90a9711b7e70e58a956",
      sha256: "f4d0237f722fee27e99f8226c31b5df74b0146e28e0ec7e0af22d2883cfd586e",
    }],
    disposition: "THEORY_PATH_AND_IMPORT_RELOCATION",
  },
);

const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const blobOid = (value) => createHash("sha1")
  .update(Buffer.from(`blob ${value.length}\0`, "utf8"))
  .update(value)
  .digest("hex");
const check = (condition, message) => { if (!condition) throw new Error(message); };
const text = (value) => value.toString("utf8").replace(/\r\n?/g, "\n");

function argument(name) {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : process.argv[index + 1];
}

function git(repository, args, encoding = "utf8") {
  return execFileSync("git", [
    "-c",
    `safe.directory=${repository.replaceAll("\\", "/")}`,
    "-C",
    repository,
    ...args,
  ], { encoding });
}

function readHistorical(repository, path) {
  return git(repository, ["show", `${historicalCommit}:${path}`], null);
}

function currentBuffers(foundationRoot) {
  const values = new Map();
  for (const mapping of mappings) {
    for (const entry of mapping.current) {
      const absolute = resolve(foundationRoot, entry.path);
      check(existsSync(absolute), `missing current foundation file: ${entry.path}`);
      values.set(entry.path, readFileSync(absolute));
    }
  }
  return values;
}

function verifyCurrent(values) {
  for (const mapping of mappings) {
    for (const entry of mapping.current) {
      const value = values.get(entry.path);
      check(value, `missing current bytes: ${entry.path}`);
      check(blobOid(value) === entry.blob, `current Git blob drift: ${entry.path}`);
      check(sha256(value) === entry.sha256, `current SHA-256 drift: ${entry.path}`);
    }
  }
}

function transformHistoricalRoot(value) {
  const original = text(value);
  const transformed = original
    .replace("chapter AFP\n", "chapter Oraclizer\n")
    .replace(
      'session Cross_Domain_State_Preservation (AFP) = "HOL-Library" +',
      'session Cross_Domain_State_Preservation = "HOL-Library" +',
    )
    .replace("    Regulatory_Action_Composition\n", "");
  check(transformed !== original, "historical ROOT transformation did not apply");
  return transformed;
}

function transformHistoricalRac(value) {
  const original = text(value);
  const transformed = original
    .replace(
      "Title:      Cross_Domain_State_Preservation/Regulatory_Action_Composition.thy",
      "Title:      Regulatory_Action_Composition/Regulatory_Action_Composition.thy",
    )
    .replace(
      "  imports Regulatory_Instance",
      '  imports "Cross_Domain_State_Preservation.Regulatory_Instance"',
    );
  check(transformed !== original, "historical RAC transformation did not apply");
  return transformed;
}

function verifyHistorical(repository, values) {
  check(git(repository, ["cat-file", "-t", historicalCommit]).trim() === "commit",
    "historical commit is not locally available");
  check(git(repository, ["show", "-s", "--format=%T", historicalCommit]).trim() === historicalTree,
    "historical tree identity drift");

  for (const mapping of mappings) {
    const historical = readHistorical(repository, mapping.historicalPath);
    check(blobOid(historical) === mapping.historicalBlob,
      `historical Git blob drift: ${mapping.historicalPath}`);
    check(sha256(historical) === mapping.historicalSha256,
      `historical SHA-256 drift: ${mapping.historicalPath}`);
    if (mapping.disposition === "BYTE_EXACT_THEORY"
        || mapping.disposition === "BYTE_EXACT_DOCUMENT_INPUT") {
      check(historical.equals(values.get(mapping.current[0].path)),
        `byte-exact mapping mismatch: ${mapping.historicalPath}`);
    }
  }

  const rootMapping = mappings.find((entry) => entry.disposition === "SESSION_PACKAGING_SPLIT");
  check(transformHistoricalRoot(readHistorical(repository, rootMapping.historicalPath))
    === text(values.get("Cross_Domain_State_Preservation/ROOT")),
  "foundation ROOT differs outside the approved session-packaging transformation");

  const racMapping = mappings.find((entry) => entry.disposition === "THEORY_PATH_AND_IMPORT_RELOCATION");
  check(transformHistoricalRac(readHistorical(repository, racMapping.historicalPath))
    === text(values.get(racMapping.current[0].path)),
  "RAC theorem source differs outside the approved title/import relocation");
}

function verifyManifest(values) {
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  check(manifest.kind === "ERC_TRUST_FORMAL_FOUNDATION_SUPERSESSION_V1"
    && manifest.status === "PASS_FORMAL_FOUNDATION_SEMANTIC_SUCCESSION",
  "formal foundation supersession manifest identity drift");
  check(manifest.historical.commit === historicalCommit
    && manifest.historical.tree === historicalTree
    && manifest.current.commit === currentCommit
    && manifest.current.tree === currentTree,
  "formal foundation commit/tree succession drift");
  check(manifest.fileMappings.length === mappings.length,
    "formal foundation mapping count drift");

  for (let index = 0; index < mappings.length; index += 1) {
    const expected = mappings[index];
    const actual = manifest.fileMappings[index];
    check(actual.historicalPath === expected.historicalPath
      && actual.historicalBlob === expected.historicalBlob
      && actual.historicalSha256 === expected.historicalSha256
      && actual.disposition === expected.disposition,
    `historical mapping drift: ${expected.historicalPath}`);
    check(JSON.stringify(actual.current) === JSON.stringify(expected.current),
      `current mapping drift: ${expected.historicalPath}`);
  }

  const lock = JSON.parse(readFileSync(lockPath, "utf8"));
  check(lock.schema === "erc-trust-formal-dependencies-public-lock-v1"
    && lock.formalFoundationDependency.repositoryCommit === currentCommit
    && lock.supersession.historicalRepositoryCommit === historicalCommit
    && lock.supersession.expectedHashesOverwritten === false,
  "public formal dependency lock drift");
  verifyCurrent(values);
}

function prepareOverlay(foundationRoot, overlayRoot, values) {
  check(!existsSync(overlayRoot), `overlay target already exists: ${overlayRoot}`);
  cpSync(resolve(foundationRoot, "Cross_Domain_State_Preservation"), overlayRoot, {
    recursive: true,
  });
  copyFileSync(
    resolve(foundationRoot, "Regulatory_Action_Composition/Regulatory_Action_Composition.thy"),
    resolve(overlayRoot, "Regulatory_Action_Composition.thy"),
  );
  const rootPath = resolve(overlayRoot, "ROOT");
  const baseRoot = text(values.get("Cross_Domain_State_Preservation/ROOT"));
  const overlayRootText = baseRoot.replace(
    "    Regulatory_Instance\n",
    "    Regulatory_Instance\n    Regulatory_Action_Composition\n",
  );
  check(overlayRootText !== baseRoot, "overlay ROOT insertion point missing");
  writeFileSync(rootPath, overlayRootText, "utf8");
  writeFileSync(resolve(overlayRoot, ".erc-trust-foundation-commit"), `${currentCommit}\n`, "utf8");
  verifyOverlay(overlayRoot, values);
}

function verifyOverlay(overlayRoot, values) {
  const marker = readFileSync(resolve(overlayRoot, ".erc-trust-foundation-commit"), "utf8").trim();
  check(marker === currentCommit, "overlay foundation commit marker drift");
  const root = readFileSync(resolve(overlayRoot, "ROOT"), "utf8");
  check((root.match(/^    Regulatory_Action_Composition$/gm) ?? []).length === 1,
    "overlay ROOT must register RAC exactly once");
  const rac = readFileSync(resolve(overlayRoot, "Regulatory_Action_Composition.thy"));
  check(rac.equals(values.get("Regulatory_Action_Composition/Regulatory_Action_Composition.thy")),
    "overlay RAC source drift");
  check(text(rac).includes('imports "Cross_Domain_State_Preservation.Regulatory_Instance"'),
    "overlay RAC import drift");
}

function hostileSelfTest(foundationRoot, values, historicalRepository) {
  let fileMutationsKilled = 0;
  for (const mapping of mappings) {
    const target = mapping.current[0].path;
    const mutant = new Map(values);
    mutant.set(target, Buffer.concat([values.get(target), Buffer.from("\n(* hostile mutation *)\n")]));
    try {
      verifyCurrent(mutant);
    } catch {
      fileMutationsKilled += 1;
    }
  }
  check(fileMutationsKilled === 14, `file mapping mutations killed ${fileMutationsKilled}/14`);

  const racMapping = mappings.find((entry) => entry.disposition === "THEORY_PATH_AND_IMPORT_RELOCATION");
  const historicalRac = readHistorical(historicalRepository, racMapping.historicalPath);
  const semanticMutant = text(values.get(racMapping.current[0].path)).replace(
    "datatype legal_rejection_reason = Undefined_Transition",
    "datatype legal_rejection_reason = Undefined_Transition_Mutant",
  );
  check(transformHistoricalRac(historicalRac) !== semanticMutant,
    "RAC theorem-body mutation survived semantic comparison");

  const overlayRoot = mkdtempSync(join(tmpdir(), "erc-trust-foundation-overlay-"));
  rmSync(overlayRoot, { recursive: true, force: true });
  try {
    prepareOverlay(foundationRoot, overlayRoot, values);
    const rootPath = resolve(overlayRoot, "ROOT");
    const rootBaseline = readFileSync(rootPath, "utf8");
    writeFileSync(rootPath, rootBaseline.replace("    Regulatory_Action_Composition\n", ""));
    let omissionKilled = false;
    try { verifyOverlay(overlayRoot, values); } catch { omissionKilled = true; }
    check(omissionKilled, "overlay omission mutation survived");
    writeFileSync(rootPath, rootBaseline);

    const racPath = resolve(overlayRoot, "Regulatory_Action_Composition.thy");
    const racBaseline = readFileSync(racPath, "utf8");
    writeFileSync(racPath, racBaseline.replace(
      'imports "Cross_Domain_State_Preservation.Regulatory_Instance"',
      "imports Regulatory_Instance",
    ));
    let importKilled = false;
    try { verifyOverlay(overlayRoot, values); } catch { importKilled = true; }
    check(importKilled, "overlay import mutation survived");
    writeFileSync(racPath, racBaseline);

    writeFileSync(resolve(overlayRoot, ".erc-trust-foundation-commit"), `${historicalCommit}\n`);
    let commitKilled = false;
    try { verifyOverlay(overlayRoot, values); } catch { commitKilled = true; }
    check(commitKilled, "overlay wrong-commit mutation survived");
  } finally {
    rmSync(overlayRoot, { recursive: true, force: true });
  }

  console.log("formal foundation hostile validation PASS: mappings 14/14; semantic 1/1; overlay 3/3");
}

const foundationArgument = argument("--foundation-root");
check(foundationArgument, "usage: --foundation-root PATH [--historical-repo PATH] [--prepare-overlay PATH] [--self-test]");
const foundationRoot = resolve(foundationArgument);
const head = git(foundationRoot, ["rev-parse", "HEAD"]).trim();
const tree = git(foundationRoot, ["show", "-s", "--format=%T", "HEAD"]).trim();
check(head === currentCommit && tree === currentTree, "current foundation checkout identity drift");

const values = currentBuffers(foundationRoot);
verifyManifest(values);
const historicalRepositoryArgument = argument("--historical-repo");
if (historicalRepositoryArgument) verifyHistorical(resolve(historicalRepositoryArgument), values);

const overlayArgument = argument("--prepare-overlay");
if (overlayArgument) prepareOverlay(foundationRoot, resolve(overlayArgument), values);

if (process.argv.includes("--self-test")) {
  check(historicalRepositoryArgument, "--self-test requires --historical-repo");
  hostileSelfTest(foundationRoot, values, resolve(historicalRepositoryArgument));
}

console.log(`formal foundation supersession PASS: ${mappings.length}/14 mappings; current ${currentCommit}`);
