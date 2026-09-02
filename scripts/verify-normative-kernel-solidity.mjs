// SPDX-License-Identifier: BSD-3-Clause
//
// Compiles the generated kernel interface with the pinned Solidity compiler and
// checks that the compiler's method identifiers, and their XOR per interface,
// equal the selectors and interface identifiers recorded by the generator.
// This closes the loop between the JavaScript selector computation and the
// compiler that implementations will actually use.

import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { resolvePinnedSolc } from "./lib/resolve-pinned-solc.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const sourcePath = "spec/generated/IERCTrustKernel.sol";
const abiPath = "spec/generated/kernel-v2-abi.json";
const lock = JSON.parse(readFileSync(resolve(root, "formal/kevm/dependencies.lock.json"), "utf8"));
const abi = JSON.parse(readFileSync(resolve(root, abiPath), "utf8"));
const failures = [];
const fail = (message) => failures.push(message);

const pinnedSolc = resolvePinnedSolc(lock.components.solc);
const input = {
  language: "Solidity",
  sources: { [sourcePath]: { content: readFileSync(resolve(root, sourcePath), "utf8") } },
  settings: {
    optimizer: { enabled: false },
    evmVersion: "cancun",
    outputSelection: { "*": { "*": ["evm.methodIdentifiers"] } },
  },
};
const command = pinnedSolc.execution === "wsl" ? "wsl.exe" : pinnedSolc.binaryPath;
const args = pinnedSolc.execution === "wsl"
  ? ["-d", pinnedSolc.distribution, "-e", pinnedSolc.binaryPath, "--standard-json"]
  : ["--standard-json"];
const output = JSON.parse(execFileSync(command, args, {
  input: JSON.stringify(input),
  encoding: "utf8",
  maxBuffer: 64 * 1024 * 1024,
  stdio: ["pipe", "pipe", "pipe"],
}));

for (const error of output.errors ?? []) {
  if (error.severity === "error") fail(`compiler error: ${error.formattedMessage ?? error.message}`);
}
const contracts = output.contracts?.[sourcePath] ?? {};

function xorOf(identifiers) {
  let acc = 0n;
  for (const selector of Object.values(identifiers)) acc ^= BigInt(`0x${selector}`);
  return `0x${acc.toString(16).padStart(8, "0")}`;
}

function compare(contractName, expectedSelectors, expectedId) {
  const compiled = contracts[contractName]?.evm?.methodIdentifiers;
  if (!compiled) {
    fail(`compiler produced no method identifiers for ${contractName}`);
    return;
  }
  const own = Object.fromEntries(
    Object.entries(compiled).filter(([signature]) => signature !== "supportsInterface(bytes4)"),
  );
  const expectedEntries = Object.entries(expectedSelectors);
  if (Object.keys(own).length !== expectedEntries.length) {
    fail(`${contractName}: compiler exposes ${Object.keys(own).length} functions, generator recorded ${expectedEntries.length}`);
  }
  for (const [signature, selector] of expectedEntries) {
    const compiledSelector = own[signature];
    if (compiledSelector === undefined) fail(`${contractName}: compiler lacks ${signature}`);
    else if (`0x${compiledSelector}` !== selector) fail(`${contractName}: selector drift for ${signature}: compiler 0x${compiledSelector}, generator ${selector}`);
  }
  const compiledId = xorOf(own);
  if (compiledId !== expectedId) fail(`${contractName}: interface identifier drift: compiler ${compiledId}, generator ${expectedId}`);
}

compare("IERCTrustKernel", abi.selectors, abi.interfaceId);
const schema = JSON.parse(readFileSync(resolve(root, "spec/erc-trust-kernel-v2.json"), "utf8"));
for (const [name, entry] of Object.entries(schema.profileInterfaces)) {
  const expected = Object.fromEntries(entry.functions.map((fn) => {
    const types = fn.inputs.map((param) => param.struct
      ? `(${schema.structs[param.struct].fields.map((field) => field.type).join(",")})`
      : param.type);
    const signature = `${fn.name}(${types.join(",")})`;
    const compiledSelector = contracts[name]?.evm?.methodIdentifiers?.[signature];
    return [signature, compiledSelector === undefined ? "missing" : `0x${compiledSelector}`];
  }));
  compare(name, expected, abi.profileInterfaceIds[name]);
}

if (failures.length) {
  for (const failure of failures) console.error(failure);
  process.exit(1);
}
console.log(`normative kernel Solidity PASS: ${pinnedSolc.versionOutput.split("\n").pop()} reproduces ${Object.keys(abi.selectors).length} kernel selectors and interface ${abi.interfaceId}`);
