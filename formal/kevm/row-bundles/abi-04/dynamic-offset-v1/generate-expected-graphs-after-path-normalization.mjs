#!/usr/bin/env node
// Rebinds the twelve calibration graph contracts only when each claim body
// below its normalized `requires` line is byte-identical. Credit remains 0.
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const familyDir = path.dirname(fileURLToPath(import.meta.url));
const rowDir = path.dirname(familyDir);
const repositoryRoot = path.resolve(rowDir, "../../../..");
const indexPath = path.join(familyDir, "claims-index-v1.json");
const graphDir = path.join(familyDir, "expected-graphs");
const mode = process.argv.includes("--write") ? "write" : process.argv.includes("--check") ? "check" : process.argv.includes("--plan") ? "plan" : null;
assert.ok(mode, "use exactly one of --write, --check, or --plan");
assert.equal(["--write", "--check", "--plan"].filter((value) => process.argv.includes(value)).length, 1);
const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const fileSha256 = (value) => sha256(fs.readFileSync(value));
const readJson = (value) => JSON.parse(fs.readFileSync(value, "utf8"));
const render = (value) => `${JSON.stringify(value, null, 2)}\n`;
const index = readJson(indexPath);
assert.equal(index.claims.length, 6);

const files = [];
for (const claim of index.claims) {
  const claimPath = path.join(repositoryRoot, ...claim.claim.path.split("/"));
  const source = fs.readFileSync(claimPath, "utf8").replaceAll("\r\n", "\n");
  assert.equal(source.split("\n")[0], 'requires "../../../trust-runtime-verification.k"', `${claim.claimId}: normalized require path`);
  const currentSourceSha256 = sha256(Buffer.from(source));
  const currentStrippedSha256 = sha256(Buffer.from(source.split("\n").slice(1).join("\n")));
  for (const side of ["canonical-positive", "mutant-negative"]) {
    const graphPath = path.join(graphDir, `${claim.endpointId}-${side}-v1.json`);
    const graph = readJson(graphPath);
    assert.equal(graph.kind, "ABI04_DYNAMIC_OFFSET_PRE_RUN_EXACT_GRAPH_CONTRACT");
    assert.equal(graph.claimId, claim.claimId);
    assert.equal(graph.side, side);
    assert.equal(graph.strippedClaimSha256, currentStrippedSha256, `${claim.claimId}::${side}: semantic claim body changed; calibration graph cannot be rebound`);
    assert.equal(graph.processExitCode, side === "canonical-positive" ? 0 : 1);
    assert.equal(graph.graph.pending, 0);
    assert.equal(graph.graph.admitted, false);
    assert.equal(graph.calibration.proofCredit, false);
    const originalSourceClaimSha256 = graph.calibration.sourcePathNormalization?.originalSourceClaimSha256 ?? graph.sourceClaimSha256;
    const expected = {
      ...graph,
      sourceClaimSha256: currentSourceSha256,
      calibration: {
        ...graph.calibration,
        sourcePathNormalization: {
          status: "BYTE_IDENTICAL_AFTER_FIRST_REQUIRES_LINE",
          originalSourceClaimSha256,
          normalizedSourceClaimSha256: currentSourceSha256,
          strippedClaimSha256: currentStrippedSha256,
          semanticClaimBodyChanged: false,
          proofRootReused: false,
          proofCredit: false,
        },
        proofCredit: false,
      },
      useBoundary: "This graph shape is calibration-only credit 0. It may judge only a fresh replay started after the normalized claim, full closure receipt, runner, and this exact contract were frozen.",
    };
    files.push({ path: graphPath, content: render(expected) });
  }
}
assert.equal(files.length, 12);
const plan = files.map((item) => {
  const actual = fs.readFileSync(item.path, "utf8").replaceAll("\r\n", "\n");
  return { path: path.relative(repositoryRoot, item.path).split(path.sep).join("/"), status: actual === item.content ? "UNCHANGED" : "CHANGED", actualSha256: sha256(actual), expectedSha256: sha256(item.content) };
});
if (mode === "write") for (const item of files) fs.writeFileSync(item.path, item.content, "utf8");
else if (mode === "check") assert.deepEqual(plan.filter((item) => item.status !== "UNCHANGED"), [], "expected graph path-normalization descendants are stale");
console.log(JSON.stringify({ status: mode === "write" ? "REBOUND_CALIBRATION_GRAPHS_CREDIT_0" : mode === "check" ? "PASS_CALIBRATION_GRAPHS_CREDIT_0" : "PASS_GRAPH_REBIND_PLAN", mode, exactGraphs: 12, semanticClaimBodiesChanged: 0, proofRootsReused: 0, proofCredit: false, centralCredit: false, changes: mode === "plan" ? plan : undefined }, null, 2));
