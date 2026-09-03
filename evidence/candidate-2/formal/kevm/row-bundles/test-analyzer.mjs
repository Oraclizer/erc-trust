import assert from "node:assert/strict";
import { analyzeProof } from "./analyze-row-proof.mjs";

const claimId = "a".repeat(64);
const base = {
  side: "positive",
  proof: { id: claimId, admitted: false, terminal: [], pending: [] },
  kcfg: { nodes: [1, 2, 3, 4], edges: [1, 2], covers: [1], stuck: [], vacuous: [] },
  logText: `PROOF PASSED: ${claimId}\nEVMC_REVERT\n`,
  expected: {
    claimId,
    exitCode: 0,
    graph: { nodes: 4, edges: 2, covers: 1, terminal: 0, stuck: 0, vacuous: 0, pending: 0, admitted: false },
    witnessTokens: ["EVMC_REVERT"],
    forbiddenLogTokens: [],
  },
};

assert.deepEqual(analyzeProof(base), base.expected.graph);
assert.deepEqual(
  analyzeProof({
    ...base,
    proof: { id: claimId, admitted: false, terminal: [] },
  }),
  base.expected.graph,
);
assert.deepEqual(
  analyzeProof({
    ...base,
    logText: `PROOF PASSED: ${claimId}\n`,
    nodeTexts: ["semantic result EVMC_REVERT"],
  }),
  base.expected.graph,
);

for (const marker of ["canceled", "timeout", "Runtime error", "Proof crashed", "BackendError"]) {
  assert.throws(() => analyzeProof({ ...base, logText: `${base.logText}${marker}\n` }), /forbidden backend\/log markers/);
}
assert.throws(() => analyzeProof({ ...base, proof: { ...base.proof, admitted: true } }), /admitted proof/);
assert.throws(() => analyzeProof({ ...base, kcfg: { ...base.kcfg, stuck: [4] } }), /graph stuck/);
assert.throws(() => analyzeProof({ ...base, kcfg: { ...base.kcfg, vacuous: [4] } }), /graph vacuous/);
assert.throws(() => analyzeProof({ ...base, proof: { ...base.proof, pending: [4] } }), /graph pending/);

const negative = {
  ...base,
  side: "negative",
  proof: { id: claimId, admitted: false, terminal: [139] },
  kcfg: { nodes: Array.from({ length: 401 }, (_, index) => index + 1), edges: Array(32), covers: [], stuck: [], vacuous: [] },
  logText: `PROOF FAILED: ${claimId}\n(262 pending and 0 failing)\n`,
  nodeTexts: ["<statusCode> EVMC_SUCCESS_NETWORK_EndStatusCode </statusCode>"],
  expected: {
    claimId,
    exitCode: 1,
    graph: { nodes: 401, edges: 32, covers: 0, terminal: 1, stuck: 0, vacuous: 0, pending: 262, admitted: false },
    witnessTokens: ["EVMC_SUCCESS_NETWORK_EndStatusCode"],
    forbiddenLogTokens: [],
  },
};
assert.deepEqual(analyzeProof(negative), negative.expected.graph);
assert.throws(
  () => analyzeProof({ ...negative, nodeTexts: ["EVMC_REVERT_NETWORK_EndStatusCode"] }),
  /missing semantic witness token/,
);

process.stdout.write(`${JSON.stringify({
  status: "PASS",
  acceptedBaseline: 1,
  acceptedExpectedNegativeWithExactPendingAndTerminalWitness: 1,
  rejectedCancellationTimeoutBackendErrorCrash: 5,
  rejectedAdmittedStuckVacuousPositivePending: 4,
  rejectedMissingNegativeTerminalWitness: 1,
}, null, 2)}\n`);
