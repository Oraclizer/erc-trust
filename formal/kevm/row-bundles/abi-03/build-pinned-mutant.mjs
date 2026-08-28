import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { resolvePinnedSolc } from "../../../../scripts/lib/resolve-pinned-solc.mjs";

const rowRoot = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(rowRoot, "../../../..");
const lockPath = join(repositoryRoot, "formal", "kevm", "dependencies.lock.json");
const canonicalInputPath = join(
  repositoryRoot,
  "evidence",
  "end-to-end-refinement",
  "runtime-binding",
  "native",
  "standard-json-input.json",
);
const inputPath = join(rowRoot, "bridge", "mutant-standard-json-input.json");
const outputPath = join(rowRoot, "bridge", "mutant-standard-json-output.json");
const sourcePath = join(rowRoot, "mutation", "mutant-TrustToken.sol");
const tokenPath = "implementation/src/TrustToken.sol";
const canonicalInput = JSON.parse(readFileSync(canonicalInputPath, "utf8"));
const canonicalSource = canonicalInput.sources[tokenPath].content;
const oldGuard = "            if xor(calldatasize(), expected) { revert(0, 0) }";
const newGuard = [
  "            if lt(calldatasize(), expected) { revert(0, 0) }",
  "            // Executable ABI-03 adequacy mutant: a trailing word is accepted",
  "            // as a successful, empty-return invocation instead of reverting.",
  "            if gt(calldatasize(), expected) { return(0, 0) }",
].join("\n");
if (canonicalSource.split(oldGuard).length !== 2) throw new Error("ABI-03 guard anchor is not unique");
const mutantSource = canonicalSource.replace(oldGuard, newGuard);
const input = structuredClone(canonicalInput);
input.sources[tokenPath].content = mutantSource;
const inputBytes = Buffer.from(`${JSON.stringify(input)}\n`, "utf8");
const lock = JSON.parse(readFileSync(lockPath, "utf8"));
const solc = lock.components.solc;
const resolvedSolc = resolvePinnedSolc(solc);

mkdirSync(dirname(inputPath), { recursive: true });
mkdirSync(dirname(sourcePath), { recursive: true });
writeFileSync(inputPath, inputBytes);
writeFileSync(sourcePath, mutantSource, "utf8");
const raw = execFileSync(
  "wsl.exe",
  ["-d", resolvedSolc.distribution, "-e", resolvedSolc.binaryPath, "--standard-json"],
  { input: inputBytes, maxBuffer: 256 * 1024 * 1024 },
);
const firstBrace = raw.indexOf(0x7b);
if (firstBrace < 0) throw new Error("pinned solc returned no JSON object");
const outputBytes = raw.subarray(firstBrace);
const output = JSON.parse(outputBytes.toString("utf8"));
const fatal = (output.errors ?? []).filter((entry) => entry.severity === "error");
if (fatal.length) throw new Error(fatal.map((entry) => entry.formattedMessage).join("\n"));
const contract = output.contracts?.[tokenPath]?.TrustToken;
if (!contract) throw new Error("mutant TrustToken compiler output missing");
writeFileSync(outputPath, outputBytes);

const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const template = Buffer.from(contract.evm.deployedBytecode.object, "hex");
console.log(JSON.stringify({
  status: "PASS",
  compilerVersion: solc.version,
  compilerBinarySha256: solc.binarySha256,
  canonicalInputSha256: sha256(readFileSync(canonicalInputPath)),
  mutantInputSha256: sha256(inputBytes),
  mutantOutputSha256: sha256(outputBytes),
  mutantSourceSha256: sha256(Buffer.from(mutantSource)),
  runtimeTemplateBytes: template.length,
  runtimeTemplateSha256: sha256(template),
}, null, 2));
