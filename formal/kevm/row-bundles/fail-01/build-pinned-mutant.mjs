#!/usr/bin/env node
// Future heavy step for FAIL-01. Do not run during the static preparation wave.
import crypto from "node:crypto";
import childProcess from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { resolvePinnedSolc } from "../../../../scripts/lib/resolve-pinned-solc.mjs";

const rowDir = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(rowDir, "../../../..");
const canonicalInputPath = path.join(repositoryRoot, "evidence", "end-to-end-refinement", "runtime-binding", "native", "standard-json-input.json");
const lockPath = path.join(repositoryRoot, "formal", "kevm", "dependencies.lock.json");
const sourceKey = "implementation/src/TrustToken.sol";
const outputDir = path.join(rowDir, "bridge", "mutant-compiler");
const inputPath = path.join(outputDir, "standard-json-input.json");
const outputPath = path.join(outputDir, "standard-json-output.json");
const sourcePath = path.join(rowDir, "mutation", "mutant-TrustToken.sol");
const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");

const canonicalInput = JSON.parse(fs.readFileSync(canonicalInputPath, "utf8"));
const canonicalSource = canonicalInput.sources[sourceKey].content;
const anchor = [
  "    function executeRegulatoryAction(TrustTypes.ActionRequest calldata request)",
  "        external",
  "        nonReentrant",
  "        returns (bytes32 receiptHash)",
  "    {",
  "        _requireCalldataLength(ACTION_CALLDATA_LENGTH);",
  "        bytes32 digest = _validateAndAuthorizeAction(request, msg.sender);",
].join("\n");
const replacement = [
  "    function executeRegulatoryAction(TrustTypes.ActionRequest calldata request)",
  "        external",
  "        nonReentrant",
  "        returns (bytes32 receiptHash)",
  "    {",
  "        _requireCalldataLength(ACTION_CALLDATA_LENGTH);",
  "        // FAIL-01 executable semantic mutant: delete typed domain rejection.",
  "        if (request.domain != TrustTypes.DOMAIN) return bytes32(0);",
  "        bytes32 digest = _validateAndAuthorizeAction(request, msg.sender);",
].join("\n");
if (canonicalSource.split(anchor).length !== 2) throw new Error("FAIL-01 mutation anchor is not unique");
const mutantSource = canonicalSource.replace(anchor, replacement);
const mutantInput = structuredClone(canonicalInput);
mutantInput.sources[sourceKey].content = mutantSource;
const inputBytes = Buffer.from(JSON.stringify(mutantInput) + "\n", "utf8");

const lock = JSON.parse(fs.readFileSync(lockPath, "utf8"));
const solc = lock.components.solc;
const resolvedSolc = resolvePinnedSolc(solc);

fs.mkdirSync(outputDir, { recursive: true });
fs.writeFileSync(inputPath, inputBytes);
fs.writeFileSync(sourcePath, mutantSource, "utf8");
const raw = childProcess.execFileSync(
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
const contract = output.contracts?.[sourceKey]?.TrustToken;
if (!contract) throw new Error("mutant TrustToken compiler output missing");
fs.writeFileSync(outputPath, outputBytes);

console.log(JSON.stringify({
  status: "MUTANT_COMPILED_NOT_PROVED",
  obligationId: "FAIL-01",
  compilerVersion: solc.version,
  compilerBinarySha256: solc.binarySha256,
  canonicalInputSha256: sha256(fs.readFileSync(canonicalInputPath)),
  mutantInputSha256: sha256(inputBytes),
  mutantOutputSha256: sha256(outputBytes),
  mutantSourceSha256: sha256(Buffer.from(mutantSource)),
  unresolvedRuntimeTemplateSha256: sha256(Buffer.from(contract.evm.deployedBytecode.object, "hex")),
  proofStatus: "NOT_RUN",
}, null, 2));
