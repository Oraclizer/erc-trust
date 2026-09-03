// Generate one concrete, diagnostic-only KEVM boundary claim from an Anvil
// steps trace. The output is a feasibility canary, never row evidence.
import { createHash } from "node:crypto";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

const value = (flag) => {
  const index = process.argv.indexOf(flag);
  return index >= 0 ? process.argv[index + 1] : undefined;
};

const boundariesPath = value("--boundaries");
const captureResultPath = value("--capture-result");
const prestatePath = value("--prestate");
const fromPc = Number(value("--from-pc"));
const toPc = Number(value("--to-pc"));
const timestamp = value("--timestamp");
const outputPath = value("--output");
if (!boundariesPath || !captureResultPath || !prestatePath || !Number.isInteger(fromPc) || !Number.isInteger(toPc) || !timestamp || !outputPath) {
  throw new Error("usage: node generate-concrete-boundary-canary-v1.mjs --boundaries FILE --capture-result FILE --prestate FILE --from-pc N --to-pc N --timestamp N --output ABSENT_FILE");
}
if (existsSync(outputPath)) throw new Error(`output already exists: ${outputPath}`);

const boundaries = JSON.parse(readFileSync(resolve(boundariesPath), "utf8"));
const capture = JSON.parse(readFileSync(resolve(captureResultPath), "utf8"));
const prestate = JSON.parse(readFileSync(resolve(prestatePath), "utf8"));
const from = boundaries.snapshots.find((snapshot) => snapshot.pc === fromPc);
const to = boundaries.snapshots.find((snapshot) => snapshot.pc === toPc);
if (!from || !to) throw new Error("requested boundary PC is absent");
if (from.depth !== to.depth || from.address !== to.address) throw new Error("boundary changes execution context");

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
const integer = (hex) => BigInt(hex).toString(10);
const address = from.address.toLowerCase();
const account = prestate.accounts[address];
if (!account) throw new Error("token account is absent from prestate");
if (capture.canonical.endpoint.toLowerCase() !== address) throw new Error("capture endpoint mismatch");

const wordStack = (words) => words.length === 0
  ? ".WordStack"
  : `${[...words].reverse().map(integer).join(" : ")} : .WordStack`;
const memory = (words) => `#parseByteStack("0x${words.map((word) => word.replace(/^0x/, "")).join("")}")`;
const storage = (entries) => {
  const rows = Object.entries(entries)
    .sort(([left], [right]) => BigInt(left) < BigInt(right) ? -1 : 1)
    .map(([key, item]) => `                  ${integer(key)} |-> ${integer(item)}`);
  return rows.length === 0 ? "                .Map" : `                (\n${rows.join("\n")}\n                )`;
};

const tokenId = integer(address);
const sender = "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266";
const senderId = integer(sender);
const fromStorage = from.tokenStorage;
const toStorage = to.tokenStorage;
if (!fromStorage || !toStorage) throw new Error("boundary storage snapshot is absent");
const fromStorageText = storage(fromStorage);
const toStorageText = storage(toStorage);
const storageTransition = fromStorageText === toStorageText
  ? fromStorageText
  : `${fromStorageText}\n                =>\n${toStorageText}`;
// The diagnostic claim disables gas accounting. In that mode KEVM preserves
// the gas cells, so every segment quantifies over and preserves the same
// _VGAS and _VMEMUSED values
// value. Copying Anvil's decreasing observations into adjacent segment
// boundaries would make otherwise identical boundaries non-composable. Anvil
// gas remains trace metadata until a separate useGas=true family is designed.
const proofUsesGas = false;
const moduleName = `TRUST-ACT-01-CONCRETE-PC-${fromPc}-TO-${toPc}-CANARY-SPEC`;

const claim = `requires "../../trust-runtime-verification.k"

// Diagnostic-only concrete boundary canary generated from an exact Anvil
// replay. It is a typed inhabitant and proof-topology feasibility input, not
// a universal theorem, row discharge, runtime_link, or composition claim.
module ${moduleName}
  imports TRUST-RUNTIME-VERIFICATION

  claim
    <kevm>
      <k> #execute </k>
      <exit-code> 1 </exit-code>
      <mode> NORMAL </mode>
      <schedule> CANCUN </schedule>
      <useGas> ${proofUsesGas} </useGas>
      <ethereum>
        <evm>
          <callState>
            <program> #trustTrustTokenRuntime() </program>
            <jumpDests> #computeValidJumpDests(#trustTrustTokenRuntime()) </jumpDests>
            <id> ${tokenId} </id>
            <caller> ${senderId} </caller>
            <callData> #parseByteStack("${capture.canonical.calldataHex}") </callData>
            <callValue> 0 </callValue>
            <wordStack>
              ${wordStack(from.stack)}
              =>
              ${wordStack(to.stack)}
            </wordStack>
            <localMem>
              ${memory(from.memory)}
              =>
              ${memory(to.memory)}
            </localMem>
            <pc> ${fromPc} => ${toPc} </pc>
            <gas> #gas(_VGAS) </gas>
            <memoryUsed> _VMEMUSED </memoryUsed>
            <callGas> _CALL_GAS </callGas>
            <static> false </static>
            <callDepth> ${from.depth - 1} </callDepth>
            <codeAddr> ${tokenId} </codeAddr>
          </callState>
          <origin> ${senderId} </origin>
          <block>
            <timestamp> ${BigInt(timestamp).toString(10)} </timestamp>
            ...
          </block>
          ...
        </evm>
        <network>
          <chainID> 31337 </chainID>
          <accounts>
            <account>
              <acctID> ${tokenId} </acctID>
              <balance> ${BigInt(account.balance).toString(10)} </balance>
              <code> #trustTrustTokenRuntime() </code>
              <storage>
${storageTransition}
              </storage>
              <origStorage> .Map </origStorage>
              <transientStorage> .Map </transientStorage>
              <nonce> ${BigInt(account.nonce).toString(10)} </nonce>
            </account>
          </accounts>
          ...
        </network>
      </ethereum>
    </kevm>

endmodule
`;

writeFileSync(resolve(outputPath), claim);
process.stdout.write(`${JSON.stringify({
  status: "PASS_GENERATED_DIAGNOSTIC_ONLY",
  module: moduleName,
  fromPc,
  toPc,
  fromIndex: from.index,
  toIndex: to.index,
  stackWords: [from.stack.length, to.stack.length],
  memoryWords: [from.memory.length, to.memory.length],
  storageKeys: [Object.keys(fromStorage).length, Object.keys(toStorage).length],
  timestamp: BigInt(timestamp).toString(10),
  gasContract: {
    proofUsesGas,
    proofCells: ["#gas(_VGAS) preserved", "_VMEMUSED preserved"],
    anvilObservedInput: BigInt(from.gas).toString(10),
    anvilObservedTarget: BigInt(to.gas).toString(10),
    anvilObservedMemoryBytes: [from.memory.length * 32, to.memory.length * 32],
  },
  outputSha256: sha256(Buffer.from(claim, "utf8")),
})}\n`);
