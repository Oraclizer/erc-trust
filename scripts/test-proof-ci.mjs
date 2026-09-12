// SPDX-License-Identifier: BSD-3-Clause
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from "node:fs";
import { join, resolve } from "node:path";
import { execFileSync, spawnSync } from "node:child_process";
import { profileIdentity, sourceIdentity, checkCatalog, scanSources, auditExport,
  requireSuccess, seal, validateState, selectPrArtifact, eligibleRun } from "./proof-ci.mjs";

const root = resolve(import.meta.dirname, "..");
mkdirSync(join(root, "out"), { recursive: true });
const temp = mkdtempSync(join(root, "out/proof-ci-test-"));
let checks = 0;
const check = (fn) => { fn(); checks++; };
const reject = (fn) => check(() => assert.throws(fn));
const rejectAsync = async (fn) => { await assert.rejects(fn); checks++; };
const put = (path, text) => { mkdirSync(resolve(path, ".."), { recursive: true }); writeFileSync(path, text); };
const env = { ISABELLE_SHA256: "tool", AFP_ADS_FUNCTOR_SHA256: "afp", FORMAL_FOUNDATION_COMMIT: "foundation", ML_SYSTEM: "polyml-5.9.2", ISABELLE_PLATFORM64: "x86_64-linux", RUNNER_OS: "Linux", RUNNER_ARCH: "X64" };
const profile = profileIdentity(env, "ubuntu-24.04", ["driver"]);
const identity = { profile, source: "1".repeat(64) };
const repository = "example/proofs";
const writer = { GITHUB_REPOSITORY: repository, GITHUB_RUN_ID: "12", GITHUB_RUN_ATTEMPT: "1", GITHUB_EVENT_NAME: "push", GITHUB_REF: "refs/heads/main", GITHUB_SHA: "a".repeat(40) };

try {
  check(() => assert.equal(profileIdentity(env, "ubuntu-24.04", ["driver"]), profile));
  for (const key of Object.keys(env)) {
    check(() => assert.notEqual(profileIdentity({ ...env, [key]: "changed" }, "ubuntu-24.04", ["driver"]), profile));
    reject(() => profileIdentity({ ...env, [key]: "" }, "ubuntu-24.04", ["driver"]));
  }
  check(() => assert.notEqual(profileIdentity(env, "different-os", ["driver"]), profile));
  check(() => assert.notEqual(profileIdentity(env, "ubuntu-24.04", ["changed-options-or-driver"]), profile));

  const source = join(temp, "source");
  mkdirSync(source);
  execFileSync("git", ["init", "-q", source]);
  put(join(source, "theory.thy"), "lemma stable");
  execFileSync("git", ["add", "."], { cwd: source });
  const before = await sourceIdentity(source);
  check(() => assert.match(before, /^[0-9a-f]{64}$/));
  put(join(source, "theory.thy"), "lemma changed");
  const after = await sourceIdentity(source);
  check(() => assert.notEqual(after, before));
  put(join(source, "generated-input.json"), "{}");
  execFileSync("git", ["add", "."], { cwd: source });
  const added = await sourceIdentity(source);
  check(() => assert.notEqual(added, after));

  check(() => assert.deepEqual(checkCatalog(root), ["ERC_TRUST"]));
  const extra = join(temp, "extra");
  put(join(extra, "formal/isabelle/ROOT"), "session Uncovered = HOL +\n");
  reject(() => checkCatalog(extra));
  const theory = join(temp, "theory");
  put(join(theory, "Model.thy"), "theory Model imports Main begin end\n");
  check(() => scanSources([theory]));
  for (const form of ["sorry", "oops", "axiomatization x", "oracle x", "by eval", "native_decide", "skip_proof", "sledgehammer", "smt_oracle"]) {
    put(join(theory, "Model.thy"), form);
    reject(() => scanSources([theory]));
  }
  reject(() => scanSources([join(temp, "missing")]));

  const exportRoot = join(temp, "export");
  const reportPath = join(exportRoot, "model-proof-trust.txt");
  const report = "status=PASS\nexplicit_root_count=1\nqualified_fact_count=2\noracle_dependency_count=0\n";
  put(reportPath, report);
  check(() => assert.equal(auditExport(exportRoot).status, "PASS"));
  for (const bad of [report.replace("PASS", "FAIL"), report.replace("root_count=1", "root_count=0"), report.replace("dependency_count=0", "dependency_count=1"), report + "status=PASS\n", "status=PASS\noracle_dependency_count=0\n"]) {
    put(reportPath, bad);
    reject(() => auditExport(exportRoot));
  }
  rmSync(reportPath);
  reject(() => auditExport(exportRoot));
  check(() => requireSuccess("success", "success"));
  for (const result of ["failure", "cancelled", "skipped", "", undefined]) {
    reject(() => requireSuccess(result, "success"));
    reject(() => requireSuccess("success", result));
  }

  const heaps = join(temp, "heaps");
  put(join(heaps, "polyml-linux/ERC_TRUST"), "heap-bytes");
  put(join(heaps, "polyml-linux/log/ERC_TRUST.db"), "database-bytes");
  const state = join(temp, "state");
  await seal(state, heaps, identity, writer);
  await validateState(state, identity, repository); checks++;
  // Different source may seed native incremental build, but PR promotion is exact.
  await validateState(state, { ...identity, source: "2".repeat(64) }, repository); checks++;
  await rejectAsync(() => validateState(state, { ...identity, profile: "other" }, repository));
  await rejectAsync(() => validateState(state, identity, "foreign/repo"));
  await rejectAsync(() => validateState(join(temp, "absent"), identity, repository));
  put(join(state, "heaps/polyml-linux/ERC_TRUST"), "corrupted");
  await rejectAsync(() => validateState(state, identity, repository));
  rmSync(state, { recursive: true });
  await seal(state, heaps, identity, { ...writer, GITHUB_EVENT_NAME: "pull_request", GITHUB_REF: "refs/pull/8/merge" });
  await rejectAsync(() => validateState(state, identity, repository));
  await validateState(state, identity, repository, "pr", "12"); checks++;
  await rejectAsync(() => validateState(state, { ...identity, source: "2".repeat(64) }, repository, "pr", "12"));
  await rejectAsync(() => validateState(state, identity, repository, "pr", "13"));
  const identityPath = join(temp, "identity.json");
  put(identityPath, JSON.stringify(identity));
  const restored = join(temp, "restored");
  const restore = (prState, mainState, destination, runId) => spawnSync(process.execPath,
    ["scripts/proof-ci.mjs", "restore", prState, mainState, destination, identityPath, runId],
    { cwd: root, env: { ...process.env, GITHUB_REPOSITORY: repository }, encoding: "utf8" });
  const recovered = restore(state, join(temp, "absent"), restored, "12");
  assert.equal(recovered.status, 0, recovered.stderr); checks++;
  assert.equal(readFileSync(join(restored, "polyml-linux/ERC_TRUST"), "utf8"), "heap-bytes"); checks++;
  const partial = join(temp, "partial");
  put(join(partial, "interrupted-copy"), "partial bytes");
  const interrupted = restore(state, join(temp, "absent"), partial, "12");
  assert.notEqual(interrupted.status, 0); checks++;
  assert.match(interrupted.stderr, /Partial restore must not be used/); checks++;
  rmSync(join(state, "heaps/polyml-linux/log/ERC_TRUST.db"));
  await rejectAsync(() => validateState(state, identity, repository, "pr", "12"));
  const fallback = restore(state, join(temp, "absent"), join(temp, "unused"), "12");
  assert.equal(fallback.status, 0, fallback.stderr); checks++;
  assert.match(fallback.stdout, /No valid state/); checks++;
  const noCache = restore(join(temp, "no-pr"), join(temp, "no-main"), join(temp, "unused"), "");
  assert.equal(noCache.status, 0, noCache.stderr); checks++;
  assert.match(noCache.stdout, /No valid state/); checks++;

  const pr = { number: 8, merged: true, merge_commit_sha: "merged", author_association: "MEMBER", base: { ref: "main", repo: { full_name: repository } }, head: { sha: "head", repo: { full_name: repository } } };
  const run = { id: 12, run_attempt: 1, event: "pull_request", status: "completed", conclusion: "success", path: ".github/workflows/proofs.yml", repository: { full_name: repository }, head_repository: { full_name: repository }, head_sha: "head", pull_requests: [{ number: 8 }], actor: { login: "maintainer" } };
  check(() => assert(eligibleRun(run, pr, repository)));
  check(() => assert(eligibleRun({ ...run, pull_requests: [] }, pr, repository)));
  for (const change of [{ conclusion: "failure" }, { status: "in_progress" }, { event: "push" }, { head_sha: "old" }, { path: ".github/workflows/other.yml" }, { head_repository: { full_name: "fork/proofs" } }, { pull_requests: [{ number: 9 }] }, { pull_requests: undefined }]) check(() => assert(!eligibleRun({ ...run, ...change }, pr, repository)));
  for (const pull_requests of [[], [{ number: 8 }], [{ number: 9 }]]) {
    for (const mismatch of [{ head_sha: "other-head" }, { head_repository: { full_name: "fork/proofs" } }, { repository: { full_name: "other/proofs" } }]) {
      check(() => assert(!eligibleRun({ ...run, pull_requests, ...mismatch }, pr, repository)));
    }
  }
  for (const change of [{ merged: false }, { author_association: "CONTRIBUTOR" }, { head: { ...pr.head, repo: { full_name: "fork/proofs" } } }]) check(() => assert(!eligibleRun(run, { ...pr, ...change }, repository)));
  let permission = "write";
  let artifactName = `isabelle-state-${profile}-${identity.source}-1`;
  const api = async (path) => {
    if (path.includes("/commits/")) return [{ number: 8 }];
    if (path.endsWith("/pulls/8")) return pr;
    if (path.includes("/workflows/")) return { workflow_runs: [run] };
    if (path.endsWith("/permission")) return { permission };
    if (path.includes("/artifacts?")) return { artifacts: [{ id: 20, name: artifactName, expired: false, workflow_run: { id: 12 } }] };
    throw Error(`Unexpected API: ${path}`);
  };
  assert.deepEqual(await selectPrArtifact(api, repository, "merged", identity), { run: "12", artifact: "20" }); checks++;
  run.pull_requests = [];
  assert.deepEqual(await selectPrArtifact(api, repository, "merged", identity), { run: "12", artifact: "20" }); checks++;
  run.pull_requests = [{ number: 9 }];
  assert.equal(await selectPrArtifact(api, repository, "merged", identity), null); checks++;
  run.pull_requests = [{ number: 8 }];
  permission = "read";
  assert.equal(await selectPrArtifact(api, repository, "merged", identity), null); checks++;
  permission = "write"; artifactName = "wrong-input";
  assert.equal(await selectPrArtifact(api, repository, "merged", identity), null); checks++;
  assert.equal(await selectPrArtifact(api, repository, "different-merge", identity), null); checks++;

  // Execute the real shell driver with a fake Isabelle process to test control
  // flow, not to claim proof success. The production checker is never replaced.
  const runtime = join(temp, "runtime");
  put(join(runtime, "formal-foundation-overlay/Model.thy"), "theory Model imports Main begin end");
  const fake = join(runtime, "Isabelle2025-2/bin/isabelle");
  put(fake, '#!/usr/bin/env bash\nset -euo pipefail\nprintf "%s\\n" "$*" >> "$RUNNER_TEMP/calls"\nif [ "$1" = build ]; then exit "${FAKE_BUILD_EXIT:-0}"; fi\nwhile [ "$1" != -O ]; do shift; done\nshift\nmkdir -p "$1"\nprintf "status=PASS\\nexplicit_root_count=1\\nqualified_fact_count=2\\noracle_dependency_count=0\\n" > "$1/model-proof-trust.txt"\n');
  const bash = process.platform === "win32" ? "C:/Program Files/Git/bin/bash.exe" : "bash";
  if (process.platform !== "win32") execFileSync("chmod", ["+x", fake]);
  for (const clean of ["false", "true"]) {
    const result = spawnSync(bash, ["scripts/run-proof-ci.sh"], { cwd: root, env: { ...process.env, RUNNER_TEMP: runtime.replaceAll("\\", "/"), CLEAN_REPLAY: clean }, encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr); checks++;
    const calls = readFileSync(join(runtime, "calls"), "utf8");
    assert(calls.includes("-D formal/isabelle")); checks++;
    assert(calls.includes("export -d")); checks++;
    assert.equal(calls.includes(" -c "), clean === "true"); checks++;
    rmSync(join(runtime, "calls"));
  }
  const failed = spawnSync(bash, ["scripts/run-proof-ci.sh"], { cwd: root, env: { ...process.env, RUNNER_TEMP: runtime.replaceAll("\\", "/"), CLEAN_REPLAY: "false", FAKE_BUILD_EXIT: "7" }, encoding: "utf8" });
  assert.equal(failed.status, 7, failed.stderr); checks++;
  assert(!readFileSync(join(runtime, "calls"), "utf8").includes("export -d")); checks++;

  const workflow = readFileSync(join(root, ".github/workflows/proofs.yml"), "utf8");
  const release = readFileSync(join(root, ".github/workflows/release.yml"), "utf8");
  const requiredPermissions = { contents: "read", actions: "read", "pull-requests": "read" };
  const permissions = (block) => Object.fromEntries(block.match(/^    permissions:\n((?:      [^\n]+\n)+)/m)[1]
    .trim().split("\n").map((line) => line.trim().split(": ")));
  for (const block of [workflow.split("\n  formal:\n")[1].split("\n    steps:")[0], release.split("\n  proofs:\n")[1].split("\n  identity:\n")[0]]) {
    check(() => assert.deepEqual(permissions(block), requiredPermissions));
    reject(() => assert.deepEqual(permissions(block.replace("      pull-requests: read\n", "")), requiredPermissions));
    reject(() => assert.deepEqual(permissions(block.replace("actions: read", "actions: write")), requiredPermissions));
  }
  check(() => assert.match(workflow, /push:\s*branches: \["main"\]/));
  check(() => assert.match(workflow, /pull_request:\s*workflow_call:/));
  check(() => assert(!/^\s+paths:/m.test(workflow)));
  check(() => assert.match(workflow, /cron: "17 4 \* \* 1"/));
  check(() => assert.match(workflow, /needs: \[gate, formal\]/));
  check(() => assert.match(workflow, /if: \$\{\{ always\(\) \}\}/));
  check(() => assert.match(workflow, /test "\$GATE_RESULT" = success\s+test "\$FORMAL_RESULT" = success/));
  check(() => assert.match(workflow, /workflow_call:\s+inputs:\s+clean:\s+type: boolean\s+default: true/));
  check(() => assert(!workflow.includes("run_formal")));
  check(() => assert.match(readFileSync(join(root, "scripts/run-proof-ci.sh"), "utf8"), /options=\(-b -v -o record_proofs=1\)/));
  console.log(`Proof CI policy: ${checks} checks passed (fixtures only; no proof computation).`);
} finally {
  rmSync(temp, { recursive: true, force: true });
}
