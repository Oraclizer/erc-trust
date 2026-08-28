// ACT-01 full-transaction claim generator (frame v3: fresh-audit minimum contract, compact representation).
//
// usage:
//   node generate-full-transaction-claims-v4.mjs --state-capture-root <feasibility output root>
//
// Frame contract (exactly the fresh-audit minimum contract, no redundancy):
//   identity   EXPLICITLY_NORMALIZED_SEMANTIC_TRANSACTION_WITNESS. The captured DynamicFee transaction is replayed as a
//              Legacy, zero-fee, empty-signature transaction with the same sender, endpoint, calldata, chain id and
//              contract storage facts. Exact captured transaction identity, gas use, fee balance transitions, OOG safety
//              and exact preservation of the captured unrelated accounts are recorded nonclaims (same precedent as the
//              discharged FAIL-05 full-transaction specification).
//   storage    <storage> ( 29 captured-nonzero entries  .Map ) => ( 55 captured-nonzero entries  .Map ).
//              The tail is the empty map on both sides: the initial state is fixed to the captured 88-key footprint
//              rather than left symbolic. Because the tail is empty the storage map is exactly the listed entries,
//              so the 59 initially-zero footprint keys (26 zero-to-nonzero + 33 unchanged-zero) are absent by
//              construction. v3 still emitted `notBool K in_keys(.Map)` for each of them; those conjuncts were
//              tautologies and v4 does not emit them;
//              the 33 keys that stay zero remain absent afterwards. The 26 changed keys reappear inside the 55 concrete
//              post entries. origStorage is left don't-care (it is write-only under #finalizeStorage and unread while
//              useGas=false). This is the KEVM idiom used by the discharged rows, scaled to the ACT-01 footprint.
//   accounts   Four named accounts (coinbase 0, sender, dependency, token) with an empty concrete tail. A K
//              cell map cannot hold two <account> cells with the same <acctID>, so the remainder is structurally disjoint
//              from the named accounts and is preserved unchanged.
//   call state Every <callState> cell is explicit: clean .Bytes/.Account/.WordStack defaults, zero value/pc/gas/memory,
//              static=false, callDepth 0 => -1 (loadTx), callGas left to loadTx (`_ => ?_`). The event-order claim stops
//              at the halted outer frame, so its call-state cells carry the halted-frame transitions instead.
//   lanes      canonical-final and control-final execute the byte-identical finalization claim against the canonical and
//              control definitions; canonical-event executes the event-order claim against the canonical definition.
// Output is deterministic (no timestamps); the manifest records the generator hash and frame counts.

import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

const inputIndex = process.argv.indexOf("--state-capture-root");
if (inputIndex < 0 || !process.argv[inputIndex + 1]) {
  throw new Error("usage: node generate-full-transaction-claims-v4.mjs --state-capture-root <path>");
}
const inputRoot = resolve(process.argv[inputIndex + 1]);
const outputRoot = resolve(import.meta.dirname, "full-transaction-v4");
const generatorPath = resolve(import.meta.dirname, "generate-full-transaction-claims-v4.mjs");
const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const fileSha256 = (path) => sha256(readFileSync(path));
const dec = (hex) => BigInt(hex).toString();
const hexKey = (value) => `0x${BigInt(value).toString(16).padStart(64, "0")}`;
const byBigInt = (a, b) => (BigInt(a) < BigInt(b) ? -1 : BigInt(a) > BigInt(b) ? 1 : 0);
const CHANGED_INITIAL_ZERO_KEY_SET_REFERENCE_SHA256 = "805ddb18ba44d43a4ef91e6bb49d667ff96dd610b7f41ed614ef873e9f937dd1";

const resultPath = resolve(inputRoot, "result.json");
const result = JSON.parse(readFileSync(resultPath, "utf8"));
if (result.status !== "PASS_FULL_TRANSACTION_FEASIBILITY_NO_CREDIT") throw new Error("state-capture result is not PASS");
const prePath = resolve(inputRoot, result.canonical.preStatePath);
const postPath = resolve(inputRoot, result.canonical.postStatePath);
const pre = JSON.parse(readFileSync(prePath, "utf8"));
const post = JSON.parse(readFileSync(postPath, "utf8"));
const tokenAddress = result.canonical.endpoint.toLowerCase();
const senderAddress = "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266";
const dependencyAddress = "0x5fbdb2315678afecb367f032d93f642f64180aa3";
const zeroAddress = "0x0000000000000000000000000000000000000000";
for (const address of [tokenAddress, senderAddress, dependencyAddress, zeroAddress]) {
  if (!pre.accounts[address]) throw new Error(`prestate account missing: ${address}`);
}
const capturedTransaction = Object.values(post.transactions).find((entry) => entry.info?.transaction_hash?.toLowerCase() === result.canonical.txHash.toLowerCase());
if (!capturedTransaction) throw new Error("canonical transaction missing from poststate dump");
const capturedBlock = post.blocks.at(-1);

// ---------------------------------------------------------------------------------------------------------------------
// Storage footprint: 88 keys, partitioned into 29 stable nonzero, 26 zero-to-nonzero and 33 unchanged zero.
// ---------------------------------------------------------------------------------------------------------------------
const preStorageObject = pre.accounts[tokenAddress].storage;
const postStorageObject = post.accounts[tokenAddress].storage;
const footprintKeys = [...new Set([...Object.keys(preStorageObject), ...Object.keys(postStorageObject), "0x1d"].map(hexKey))].sort(byBigInt);
const preByKey = Object.fromEntries(Object.entries(preStorageObject).map(([key, value]) => [hexKey(key), BigInt(value)]));
const postByKey = Object.fromEntries(Object.entries(postStorageObject).map(([key, value]) => [hexKey(key), BigInt(value)]));
const preValue = (key) => preByKey[key] ?? 0n;
const postValue = (key) => postByKey[key] ?? 0n;
const preNonzeroKeys = footprintKeys.filter((key) => preValue(key) !== 0n);
const postNonzeroKeys = footprintKeys.filter((key) => postValue(key) !== 0n);
const changedKeys = footprintKeys.filter((key) => preValue(key) !== postValue(key));
const unchangedZeroKeys = footprintKeys.filter((key) => preValue(key) === 0n && postValue(key) === 0n);
const initialZeroKeys = footprintKeys.filter((key) => preValue(key) === 0n); // 26 changed + 33 unchanged-zero = 59
const finalZeroKeys = footprintKeys.filter((key) => postValue(key) === 0n);
if (footprintKeys.length !== 88) throw new Error(`footprint key count drift: ${footprintKeys.length}`);
if (preNonzeroKeys.length !== 29) throw new Error(`pre nonzero key count drift: ${preNonzeroKeys.length}`);
if (postNonzeroKeys.length !== 55) throw new Error(`post nonzero key count drift: ${postNonzeroKeys.length}`);
if (changedKeys.length !== 26) throw new Error(`changed key count drift: ${changedKeys.length}`);
if (unchangedZeroKeys.length !== 33) throw new Error(`unchanged zero key count drift: ${unchangedZeroKeys.length}`);
if (initialZeroKeys.length !== 59) throw new Error(`initial zero key count drift: ${initialZeroKeys.length}`);
if (finalZeroKeys.length !== 33) throw new Error(`final zero key count drift: ${finalZeroKeys.length}`);
if (changedKeys.some((key) => preValue(key) !== 0n)) throw new Error("ACT-01 named frame requires every changed key to be zero before the transaction");
if (changedKeys.some((key) => postValue(key) === 0n)) throw new Error("ACT-01 named frame requires every changed key to be nonzero after the transaction");
if (preNonzeroKeys.some((key) => preValue(key) === postValue(key) ? false : !changedKeys.includes(key))) throw new Error("pre nonzero partition inconsistent");
if (!unchangedZeroKeys.includes(hexKey("0x1d"))) throw new Error("reentrancy slot 0x1d must be an unchanged zero footprint key");

const changedInitialZeroKeySetSha256 = sha256(`${changedKeys.join("\n")}\n`);
if (changedInitialZeroKeySetSha256 !== CHANGED_INITIAL_ZERO_KEY_SET_REFERENCE_SHA256) {
  throw new Error(`changed initial-zero key set drift: ${changedInitialZeroKeySetSha256}`);
}
const changedInitialZeroKeySet = {
  keyCount: changedKeys.length,
  encoding: "sorted ascending 0x-prefixed 32-byte hex keys, one per line, trailing newline",
  sha256: changedInitialZeroKeySetSha256,
  referenceSha256: CHANGED_INITIAL_ZERO_KEY_SET_REFERENCE_SHA256,
  matchesReference: true,
  keysHex: changedKeys,
};

// ---------------------------------------------------------------------------------------------------------------------
// Rendering helpers.
// ---------------------------------------------------------------------------------------------------------------------
const indent = (depth) => " ".repeat(depth);
function renderStorageSide(nonzeroKeys, depth) {
  const lines = nonzeroKeys.map((key) => `${indent(depth + 2)}${dec(key)} |-> ${(nonzeroKeys === preNonzeroKeys ? preValue(key) : postValue(key)).toString()}`);
  lines.push(`${indent(depth + 2)}.Map`);
  return `${indent(depth)}(\n${lines.join("\n")}\n${indent(depth)})`;
}
const preStorageSide = renderStorageSide(preNonzeroKeys, 16);
const postStorageSide = renderStorageSide(postNonzeroKeys, 16);
// The 59 initially-zero footprint keys are still computed and checked above, but they are
// no longer emitted as requires conjuncts: with the tail concretised to `.Map` the storage
// map is exactly the listed entries, so `notBool K in_keys(.Map)` is a tautology. It
// constrains nothing and is re-expanded by the rewriter on every simplification pass.
const droppedVacuousRestAbsenceAtoms = initialZeroKeys.length;

const calldata = result.canonical.calldataHex.toLowerCase();
const receiptHash = result.canonical.callReceiptHash.toLowerCase();
const tokenId = dec(tokenAddress);
const senderId = dec(senderAddress);
const dependencyId = dec(dependencyAddress);
const receiptInt = dec(receiptHash);
const logs = capturedTransaction.receipt.logs;
if (logs.length !== 2) throw new Error("expected two committed protocol logs");
function renderLog(entry) {
  const topics = entry.topics.map((topic) => `ListItem(${dec(topic)})`).join(" ");
  return `{ ${dec(entry.address)} | ${topics} | #parseByteStack("${entry.data.toLowerCase()}") }`;
}
const logList = logs.map((entry) => `ListItem(${renderLog(entry)})`).join(" ");

function renderAccounts() {
  return `
              <account>
                <acctID> 0 </acctID>
                <balance> 0 </balance>
                <code> .Bytes </code>
                <storage> .Map </storage>
                <origStorage> .Map </origStorage>
                <transientStorage> .Map </transientStorage>
                <nonce> 0 </nonce>
              </account>
              <account>
                <acctID> ${senderId} </acctID>
                <balance> 1000000000 </balance>
                <code> .Bytes </code>
                <storage> .Map </storage>
                <origStorage> .Map </origStorage>
                <transientStorage> .Map </transientStorage>
                <nonce> 0 => 1 </nonce>
              </account>
              <account>
                <acctID> ${dependencyId} </acctID>
                <balance> 0 </balance>
                <code> #trustMockBoundDependencyRuntime() </code>
                <storage> .Map </storage>
                <origStorage> .Map </origStorage>
                <transientStorage> .Map </transientStorage>
                <nonce> 1 </nonce>
              </account>
              <account>
                <acctID> ${tokenId} </acctID>
                <balance> 0 </balance>
                <code> #trustTrustTokenRuntime() </code>
                <storage>
${preStorageSide}
                  =>
${postStorageSide}
                </storage>
                <origStorage> _ => ?_ </origStorage>
                <transientStorage> .Map </transientStorage>
                <nonce> 1 </nonce>
              </account>`;
}

const message = `
              <message>
                <msgID> 0 </msgID>
                <txNonce> 0 </txNonce>
                <txGasPrice> 0 </txGasPrice>
                <txGasLimit> 15000000 </txGasLimit>
                <to> ${tokenId} </to>
                <value> 0 </value>
                <sigV> 0 </sigV>
                <sigR> .Bytes </sigR>
                <sigS> .Bytes </sigS>
                <data> #parseByteStack("${calldata}") </data>
                <txAccess> [ .JSONs ] </txAccess>
                <txChainID> 31337 </txChainID>
                <txPriorityFee> 0 </txPriorityFee>
                <txMaxFee> 0 </txMaxFee>
                <txType> Legacy </txType>
                <txMaxBlobFee> 0 </txMaxBlobFee>
                <txVersionedHashes> .List </txVersionedHashes>
                <txAuthList> .List </txAuthList>
              </message>`;

// Call-state and transaction-scope cells differ between the two targets:
//   finalization: the outer frame has been popped and the transaction finalized (clean frame restored, substate cleared).
//   event order:  the outer frame is halted but not yet popped (live halted frame, substate still populated).
const finalizationFrame = {
  callStack: ".List",
  interimStates: ".List",
  touchedAccounts: ".Set",
  accessedAccounts: ".Set",
  accessedStorage: ".Map",
  callState: `
            <program> .Bytes </program>
            <jumpDests> .Bytes </jumpDests>
            <id> .Account </id>
            <caller> .Account </caller>
            <callData> .Bytes </callData>
            <callValue> 0 </callValue>
            <wordStack> .WordStack </wordStack>
            <localMem> .Bytes </localMem>
            <pc> 0 </pc>
            <gas> 0:Gas => ?_ </gas>
            <memoryUsed> 0 </memoryUsed>
            <callGas> _ => ?_ </callGas>
            <static> false </static>
            <callDepth> 0 => -1 </callDepth>
            <codeAddr> .Account </codeAddr>`,
  txPending: "ListItem(0) => .List",
};
const eventFrame = {
  callStack: ".List => ?_",
  interimStates: ".List => ?_",
  touchedAccounts: ".Set => ?_",
  accessedAccounts: ".Set => ?_",
  accessedStorage: ".Map => ?_",
  callState: `
            <program> .Bytes => #trustTrustTokenRuntime() </program>
            <jumpDests> .Bytes => ?_ </jumpDests>
            <id> .Account => ${tokenId} </id>
            <caller> .Account => ${senderId} </caller>
            <callData> .Bytes => #parseByteStack("${calldata}") </callData>
            <callValue> 0 </callValue>
            <wordStack> .WordStack => ?_ </wordStack>
            <localMem> .Bytes => ?_ </localMem>
            <pc> 0 => ?_ </pc>
            <gas> 0:Gas => ?_ </gas>
            <memoryUsed> 0 => ?_ </memoryUsed>
            <callGas> _ => ?_ </callGas>
            <static> false </static>
            <callDepth> 0 </callDepth>
            <codeAddr> .Account => ${tokenId} </codeAddr>`,
  txPending: "ListItem(0)",
};

function claim({ moduleName, kTarget, logTarget, frame }) {
  return `requires "../../../trust-runtime-verification.k"

module ${moduleName}
  imports TRUST-RUNTIME-VERIFICATION

  claim
    <kevm>
      <k> loadTx(${senderId}) => ${kTarget} </k>
      <exit-code> 1 </exit-code>
      <mode> NORMAL </mode>
      <schedule> CANCUN </schedule>
      <useGas> false </useGas>
      <ethereum>
        <evm>
          <output> .Bytes => #buf(32, ${receiptInt}) </output>
          <statusCode> .StatusCode => EVMC_SUCCESS </statusCode>
          <callStack> ${frame.callStack} </callStack>
          <interimStates> ${frame.interimStates} </interimStates>
          <touchedAccounts> ${frame.touchedAccounts} </touchedAccounts>
          <callState>${frame.callState}
          </callState>
          <substate>
            <selfDestruct> .Set </selfDestruct>
            <log> .List => ${logTarget} </log>
            <refund> 0 </refund>
            <accessedAccounts> ${frame.accessedAccounts} </accessedAccounts>
            <accessedStorage> ${frame.accessedStorage} </accessedStorage>
            <createdAccounts> .Set </createdAccounts>
          </substate>
          <gasPrice> 0 </gasPrice>
          <origin> .Account => ${senderId} </origin>
          <block>
            <coinbase> 0 </coinbase>
            <timestamp> 1700000000 </timestamp>
            <gasLimit> 30000000 </gasLimit>
            <gasUsed> 0:Gas => ?_ </gasUsed>
            <baseFee> 0 </baseFee>
            ...
          </block>
          ...
        </evm>
        <network>
          <chainID> 31337 </chainID>
          <accounts>${renderAccounts()}
          </accounts>
          <txOrder> .List </txOrder>
          <txPending> ${frame.txPending} </txPending>
          <messages>${message}
          </messages>
          <withdrawalsPending> .List </withdrawalsPending>
          <withdrawalsOrder> .List </withdrawalsOrder>
          <withdrawals> .Bag </withdrawals>
          <requests>
            <depositRequests> .Bytes </depositRequests>
            <withdrawalRequests> .Bytes </withdrawalRequests>
            <consolidationRequests> .Bytes </consolidationRequests>
          </requests>
          ...
        </network>
      </ethereum>
    </kevm>

endmodule
`;
}

const finalizeClaim = claim({
  moduleName: "TRUST-ACT-01-FULL-TRANSACTION-FINALIZATION-SPEC",
  kTarget: "#finalizeBlock",
  logTarget: "?_",
  frame: finalizationFrame,
});
const eventClaim = claim({
  moduleName: "TRUST-ACT-01-FULL-TRANSACTION-EVENT-ORDER-SPEC",
  kTarget: `#halt ~> #finishTx ~> #finalizeTx(false, Ctxfloor(CANCUN, #parseByteStack("${calldata}"))) ~> startTx`,
  logTarget: logList,
  frame: eventFrame,
});

mkdirSync(outputRoot, { recursive: true });
const finalizePath = resolve(outputRoot, "full-transaction-finalization-spec.k");
const eventPath = resolve(outputRoot, "full-transaction-event-order-spec.k");
writeFileSync(finalizePath, finalizeClaim);
writeFileSync(eventPath, eventClaim);
const finalizeSha256 = fileSha256(finalizePath);
const eventSha256 = fileSha256(eventPath);
const countMatches = (text, pattern) => (text.match(pattern) ?? []).length;
const manifest = {
  schemaVersion: 3,
  kind: "ACT01_FULL_TRANSACTION_CLAIM_GENERATION_V1",
  obligationId: "ACT-01",
  frameVersion: "v4-vacuous-rest-absence-requires-removed",
  generator: {
    path: "formal/kevm/row-bundles/act-01/generate-full-transaction-claims-v4.mjs",
    sha256: fileSha256(generatorPath),
  },
  sourceCapture: {
    resultRef: "external-scratch/erc-trust-m4-wave4-act01-full-transaction-feasibility-v1-002/result.json",
    resultSha256: fileSha256(resultPath),
    preStateSha256: fileSha256(prePath),
    postStateSha256: fileSha256(postPath),
    calldataSha256: result.canonical.calldataSha256,
  },
  runtime: {
    canonicalSha256: result.runtime.canonicalSha256,
    controlSha256: result.runtime.controlSha256,
  },
  claimIdentity: {
    classification: "EXPLICITLY_NORMALIZED_SEMANTIC_TRANSACTION_WITNESS",
    precedent: "formal/kevm/specs/full-transaction-generic-dispatcher-revert-spec.k (discharged FAIL-05: txType Legacy, gasPrice 0, baseFee 0, useGas false)",
    captured: {
      transactionType: "DynamicFee (type 2)",
      senderNonce: `${result.canonical.senderNonceBefore} -> ${result.canonical.senderNonceAfter}`,
      blockTimestamp: BigInt(capturedBlock.header.timestamp).toString(),
      blockNumber: BigInt(capturedBlock.header.number).toString(),
      baseFeePerGas: BigInt(capturedBlock.header.baseFeePerGas).toString(),
      gasUsed: result.canonical.gasUsed,
      accountCount: Object.keys(pre.accounts).length,
    },
    normalized: {
      transactionType: "Legacy",
      txGasPrice: "0",
      baseFee: "0",
      useGas: false,
      senderNonce: "0 -> 1",
      blockTimestamp: "1700000000",
      signature: "empty (loadTx(sender) starts after sender derivation)",
      senderBalance: "1000000000 (invented, unchanged because every fee term is zero)",
      namedAccounts: ["coinbase 0", senderAddress, dependencyAddress, tokenAddress],
      accountRemainder: "none (the account cell is closed after the four captured accounts, matching the discharged FAIL-05 precedent)",
    },
    timestampJustification: "calldata validAfter/validBefore window admits 1700000000; the runtime reads only block.timestamp and chainid, and the captured storage facts do not encode the block timestamp",
    residualNonclaims: [
      "exact captured DynamicFee transaction identity",
      "gas use, fee balance transition",
      "OOG safety",
      "captured unrelated accounts exact preservation",
    ],
  },
  storageFrame: {
    encoding: "TWENTYNINE_PRE_PLUS_FIFTYFIVE_POST_NONZERO_ENTRIES_WITH_SHARED_REMAINDER",
    footprintKeyCount: footprintKeys.length,
    preNonzeroEntryCount: preNonzeroKeys.length,
    postNonzeroEntryCount: postNonzeroKeys.length,
    changedZeroToNonzeroKeyCount: changedKeys.length,
    unchangedZeroKeyCount: unchangedZeroKeys.length,
    initialZeroKeyCount: initialZeroKeys.length,
    finalZeroKeyCount: finalZeroKeys.length,
    restAbsenceAtomCount: 0,
    droppedVacuousRestAbsenceAtomCount: droppedVacuousRestAbsenceAtoms,
    remainderVariable: ".Map (empty concrete tail; initial state fixed to the captured 88-key footprint, no symbolic remainder)",
    initialZeroBinding: "all 59 initially-zero footprint keys are absent by construction: the tail is the empty map, so the storage map is exactly the listed entries. The v3 requires conjuncts asserting that absence against `.Map` were tautologies and are no longer emitted",
    finalZeroBinding: "the 33 final-zero keys stay absent because the tail is the empty map on both sides; the 26 changed keys reappear as concrete post entries",
    origStorage: "don't-care (write-only under #finalizeStorage; unread while useGas=false)",
    changedInitialZeroKeySet,
  },
  accountFrame: {
    encoding: "FOUR_NAMED_ACCOUNTS_PLUS_EMPTY_TAIL",
    disjointness: "structural: a K cell map cannot contain two <account> cells with the same <acctID>",
  },
  callStateFrame: {
    finalization: "clean defaults restored by #popCallStack; callDepth 0 => -1 from loadTx; callGas _ => ?_; gas 0:Gas => ?_",
    eventOrder: "halted outer frame before #finishTx: program/jumpDests/id/caller/callData/codeAddr transitions, callDepth 0, static false",
  },
  lanes: [
    { lane: "canonical-final", claim: "full-transaction-finalization-spec.k", claimSha256: finalizeSha256, definitionRef: "external-definition/canonical-runtime-verification", expectedExitCode: 0 },
    { lane: "control-final", claim: "full-transaction-finalization-spec.k", claimSha256: finalizeSha256, definitionRef: "external-definition/act-01-state-restoration-control", expectedExitCode: 1, unchangedClaimAcrossDefinitions: true },
    { lane: "canonical-event", claim: "full-transaction-event-order-spec.k", claimSha256: eventSha256, definitionRef: "external-definition/canonical-runtime-verification", expectedExitCode: 0 },
  ],
  claims: [
    { path: "formal/kevm/row-bundles/act-01/full-transaction-v4/full-transaction-finalization-spec.k", sha256: finalizeSha256, module: "TRUST-ACT-01-FULL-TRANSACTION-FINALIZATION-SPEC" },
    { path: "formal/kevm/row-bundles/act-01/full-transaction-v4/full-transaction-event-order-spec.k", sha256: eventSha256, module: "TRUST-ACT-01-FULL-TRANSACTION-EVENT-ORDER-SPEC" },
  ],
  expected: {
    finalFrozenTarget: "1",
    lifecycle: "APPLIED",
    senderNonceDelta: 1,
    committedLogCount: logs.length,
    receiptHash,
    preNonzeroEntryCount: preNonzeroKeys.length,
    postNonzeroEntryCount: postNonzeroKeys.length,
    changedKeyCount: changedKeys.length,
    restAbsenceAtomCount: 0,
    droppedVacuousRestAbsenceAtomCount: droppedVacuousRestAbsenceAtoms,
    finalizationClaimPreEntryOccurrences: countMatches(finalizeClaim, /\|-> /g),
    finalizationClaimRestAbsenceOccurrences: countMatches(finalizeClaim, /in_keys\(\.Map\)/g),
    eventClaimPreEntryOccurrences: countMatches(eventClaim, /\|-> /g),
  },
  proofExecuted: false,
  proofCredit: false,
  centralCredit: false,
};
const manifestPath = resolve(outputRoot, "manifest.json");
writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
process.stdout.write(`${JSON.stringify({ status: "PASS_GENERATED_NO_PROOF", finalizeSha256, eventSha256, manifestSha256: fileSha256(manifestPath), generatorSha256: manifest.generator.sha256, finalizeBytes: finalizeClaim.length, eventBytes: eventClaim.length, changedInitialZeroKeySetSha256 })}\n`);
