import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const outputDirectory = resolve(process.argv[2] ?? join(scriptDirectory, "out"));
const isabelleRootArgument = process.argv[3];
const adsFunctorArgument = process.argv[4];
const formalFoundationArgument = process.argv[5];
if (!isabelleRootArgument || !adsFunctorArgument || !formalFoundationArgument) {
  throw new Error(
    "Usage: node reverse-check-manifest.mjs [output-directory] " +
    "<isabelle-root> <ads-functor> <formal-foundation>");
}
const isabelleRoot = resolve(isabelleRootArgument);
const adsFunctor = resolve(adsFunctorArgument);
const formalFoundationDirectory = resolve(formalFoundationArgument);
const formalFoundationParent = dirname(formalFoundationDirectory);
const sessionDirectory = resolve(scriptDirectory, "..", "..");
const repositoryRoot = resolve(sessionDirectory, "..");

const shaBytes = (bytes) => createHash("sha256").update(bytes).digest("hex").toUpperCase();
const shaFile = (path) => shaBytes(readFileSync(path));
const canonicalLine = (value) => JSON.stringify(value);
const readJsonLines = (path) => readFileSync(path, "utf8").trimEnd().split("\n").map((line) => JSON.parse(line));
const readTsvLines = (path) => {
  const normalized = readFileSync(path, "utf8").replaceAll("\r\n", "\n");
  const withoutFinalNewline = normalized.endsWith("\n") ? normalized.slice(0, -1) : normalized;
  return withoutFinalNewline.split("\n");
};

const sourceFiles = [
  "ROOTS",
  "Cross_Domain_State_Preservation/ROOT",
  "Cross_Domain_State_Preservation/State_Preservation.thy",
  "Cross_Domain_State_Preservation/Regulatory_Instance.thy",
  "Cross_Domain_State_Preservation/Regulatory_Action_Composition.thy",
  "ERC_TRUST/ROOT",
  "ERC_TRUST/Regulatory_Execution_Semantics.thy",
  "ERC_TRUST/RCP_Action_Mapping.thy",
  "ERC_TRUST/Token_Compatibility.thy",
  "ERC_TRUST/Regulatory_Execution_Simulation.thy",
  "ERC_TRUST/Privileged_Governance.thy",
  "ERC_TRUST/Executable_Regulatory_Kernel.thy",
  "ERC_TRUST/Claim_Boundary.thy",
  "ERC_TRUST/Proof_Audit.thy",
  "ERC_TRUST/evidence/model-verification/model-claim-matrix.md",
  "ERC_TRUST/evidence/model-verification/generate-manifest.ps1",
  "ERC_TRUST/evidence/model-verification/run-negative-mutations.ps1",
  "ERC_TRUST/evidence/model-verification/run-trust-closure.ps1",
  "ERC_TRUST/evidence/model-verification/reverse-check-manifest.mjs",
];

const failures = [];
const check = (condition, label, details = undefined) => {
  if (!condition) failures.push({ label, details });
};

const hashLines = sourceFiles.map((relativePath) => {
  const sourceRoot = relativePath.startsWith("Cross_Domain_State_Preservation/")
    ? formalFoundationParent
    : repositoryRoot;
  const absolutePath = join(sourceRoot, ...relativePath.split("/"));
  const bytes = readFileSync(absolutePath);
  return `${relativePath}\t${shaBytes(bytes)}\t${bytes.length}`;
}).sort((left, right) => left.localeCompare(right, "en", { sensitivity: "case" }));
const hashListText = `${hashLines.join("\n")}\n`;
const sourceHashListHash = shaBytes(Buffer.from(hashListText, "utf8"));

const actions = ["FREEZE", "SEIZE", "CONFISCATE", "RESTRICT", "RECOVER", "LIQUIDATE"];
const scenarios = ["SUCCESS", "DENIED", "DEPENDENCY_FAILURE"];
const states = ["ACTIVE", "FROZEN", "SEIZED", "CONFISCATED", "RESTRICTED"];
const labels = ["FREEZE", "SEIZE", "CONFISCATE", "RESTRICT", "UNFREEZE", "UNRESTRICT", "RELEASE"];
const expectedTrustKeys = actions.flatMap((action) =>
  scenarios.map((scenario) => `TRUST|${action}|${scenario}`));
const expectedFoundationKeys = states.flatMap((state) =>
  labels.map((label) => `FOUNDATION|${state}|${label}`));

const toCygwinPath = (windowsPath) => {
  const normalized = resolve(windowsPath);
  return `/cygdrive/${normalized[0].toLowerCase()}${normalized.slice(2).replaceAll("\\", "/")}`;
};
const findNamedFile = (directory, name) => {
  for (const entry of readdirSync(directory)) {
    const candidate = join(directory, entry);
    if (statSync(candidate).isDirectory()) {
      const nested = findNamedFile(candidate, name);
      if (nested) return nested;
    } else if (entry === name) {
      return candidate;
    }
  }
  return undefined;
};

const independentExportDirectory = join(
  outputDirectory, "kernel-export-reverse", new Date().toISOString().replaceAll(/[-:.]/g, ""));
mkdirSync(independentExportDirectory, { recursive: true });
const isabelleBash = join(isabelleRoot, "contrib", "cygwin", "bin", "bash.exe");
const isabelle = `${toCygwinPath(isabelleRoot)}/bin/isabelle`;
const exportCommand =
  `export PATH=/usr/local/bin:/usr/bin:/bin; '${isabelle}' export ` +
  `-d '${toCygwinPath(adsFunctor)}' ` +
  `-d '${toCygwinPath(formalFoundationDirectory)}' ` +
  `-d '${toCygwinPath(repositoryRoot)}' ` +
  `-x '*:erc-trust/*-kernel.tsv' ` +
  `-O '${toCygwinPath(independentExportDirectory)}' ERC_TRUST`;
const exportResult = spawnSync(
  isabelleBash, ["--noprofile", "--norc", "-c", exportCommand],
  { encoding: "utf8" });
check(exportResult.status === 0, "isabelle.independent-export", {
  status: exportResult.status,
  stdout: exportResult.stdout,
  stderr: exportResult.stderr,
});
const independentTrustKernel = findNamedFile(independentExportDirectory, "trust-kernel.tsv");
const independentFoundationKernel = findNamedFile(independentExportDirectory, "foundation-kernel.tsv");
check(Boolean(independentTrustKernel), "isabelle.trust-kernel-present");
check(Boolean(independentFoundationKernel), "isabelle.foundation-kernel-present");

const parseTrustKernel = (path) => readTsvLines(path).map((line) => {
  const columns = line.split("\t");
  check(columns.length === 13, "isabelle.trust-kernel-column-count", line);
  return {
    key: columns[0],
    input: {
      action: columns[1], scenario: columns[2], initialState: columns[3],
    },
    command: columns[4],
    outcome: columns[5],
    targetState: columns[6] === "-" ? null : columns[6],
    rcpAction: columns[1],
    descriptor: {
      reversibility: columns[7], ownership: columns[8], finality: columns[9],
    },
    transferGate: columns[10] === "true",
    requiredObservable: columns[11],
    writeSet: columns[12] === "" ? [] : columns[12].split(";"),
    sourceTheoryHash: sourceHashListHash,
  };
});
const parseFoundationKernel = (path) => readTsvLines(path).map((line) => {
  const columns = line.split("\t");
  check(columns.length === 6, "isabelle.foundation-kernel-column-count", line);
  return {
    key: columns[0],
    input: { state: columns[1], transitionLabel: columns[2] },
    command: columns[3],
    outcome: columns[4],
    targetState: columns[5],
    sourceTheoryHash: sourceHashListHash,
  };
});
const expectedTrustRows = independentTrustKernel ? parseTrustKernel(independentTrustKernel) : [];
const expectedFoundationRows = independentFoundationKernel
  ? parseFoundationKernel(independentFoundationKernel)
  : [];

const trustPath = join(outputDirectory, "trust-manifest.body.jsonl");
const foundationPath = join(outputDirectory, "foundation-manifest.body.jsonl");
const envelopePath = join(outputDirectory, "manifest-envelope.json");
const hashListPath = join(outputDirectory, "sha256.tsv");
const actualTrustRows = readJsonLines(trustPath);
const actualFoundationRows = readJsonLines(foundationPath);
const envelope = JSON.parse(readFileSync(envelopePath, "utf8"));

const checkRows = (name, actual, expected) => {
  check(actual.length === expected.length, `${name}.row-count`, { actual: actual.length, expected: expected.length });
  check(new Set(actual.map((row) => row.key)).size === actual.length, `${name}.duplicate-keys`);
  check(new Set(expected.map((row) => row.key)).size === expected.length, `${name}.checker-keyspace-unique`);
  const expectedByKey = new Map(expected.map((row) => [row.key, row]));
  for (const row of actual) {
    check(expectedByKey.has(row.key), `${name}.unknown-key`, row.key);
    if (expectedByKey.has(row.key)) {
      check(canonicalLine(row) === canonicalLine(expectedByKey.get(row.key)), `${name}.semantic-row`, row.key);
    }
  }
  const actualKeys = new Set(actual.map((row) => row.key));
  for (const row of expected) check(actualKeys.has(row.key), `${name}.missing-key`, row.key);
};

checkRows("trust", actualTrustRows, expectedTrustRows);
checkRows("foundation", actualFoundationRows, expectedFoundationRows);
check(
  canonicalLine(expectedTrustRows.map((row) => row.key)) === canonicalLine(expectedTrustKeys),
  "trust.independent-keyspace");
check(
  canonicalLine(expectedFoundationRows.map((row) => row.key)) === canonicalLine(expectedFoundationKeys),
  "foundation.independent-keyspace");
check(readFileSync(hashListPath, "utf8") === hashListText, "source.hash-list-content");
check(envelope.sourceHashListHash === sourceHashListHash, "source.hash-list-hash");
check(envelope.generatorHash === shaFile(join(scriptDirectory, "generate-manifest.ps1")), "tool.generator-hash");
check(envelope.reverseCheckerHash === shaFile(fileURLToPath(import.meta.url)), "tool.reverse-checker-hash");
const generatorTrustKernel = join(outputDirectory, "isabelle-trust-kernel.tsv");
const generatorFoundationKernel = join(outputDirectory, "isabelle-foundation-kernel.tsv");
check(envelope.isabelleKernel.trustKernelSha256 === shaFile(generatorTrustKernel), "envelope.trust-kernel-hash");
check(
  envelope.isabelleKernel.foundationKernelSha256 === shaFile(generatorFoundationKernel),
  "envelope.foundation-kernel-hash");
check(readFileSync(generatorTrustKernel, "utf8") === readFileSync(independentTrustKernel, "utf8"), "isabelle.trust-kernel-independent-match");
check(
  readFileSync(generatorFoundationKernel, "utf8") === readFileSync(independentFoundationKernel, "utf8"),
  "isabelle.foundation-kernel-independent-match");
check(envelope.trustManifest.expectedRows === 18 && envelope.trustManifest.actualRows === 18, "envelope.trust-counts");
check(
  envelope.foundationManifest.expectedRows === 35 && envelope.foundationManifest.actualRows === 35,
  "envelope.foundation-counts");
check(envelope.trustManifest.bodySha256 === shaFile(trustPath), "envelope.trust-body-hash");
check(
  envelope.foundationManifest.bodySha256 === shaFile(foundationPath),
  "envelope.foundation-body-hash");
const combinedHash = shaBytes(
  Buffer.from(`${shaFile(trustPath)}\n${shaFile(foundationPath)}\n`, "utf8"));
check(envelope.manifestSha256 === combinedHash, "envelope.manifest-hash");
check(envelope.claim === "mechanically verified regulatory dynamics over the declared domain", "envelope.claim-boundary");

const report = {
  status: failures.length === 0 ? "PASS" : "FAIL",
  checker: "independent-node-reenumeration-v1",
  outputDirectory,
  trustRows: actualTrustRows.length,
  foundationRows: actualFoundationRows.length,
  uniqueTrustKeys: new Set(actualTrustRows.map((row) => row.key)).size,
  uniqueFoundationKeys: new Set(actualFoundationRows.map((row) => row.key)).size,
  sourceHashListHash,
  failures,
};
writeFileSync(join(outputDirectory, "reverse-check-report.json"), `${JSON.stringify(report)}\n`, { encoding: "utf8" });
process.stdout.write(`${JSON.stringify(report)}\n`);
process.exitCode = failures.length === 0 ? 0 : 1;
