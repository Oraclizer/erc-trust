// SPDX-License-Identifier: BSD-3-Clause
// Reusable state is an input to Isabelle, never a replacement for its build.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { createReadStream, existsSync, readFileSync, readdirSync, lstatSync,
  mkdirSync, cpSync, writeFileSync, appendFileSync } from "node:fs";
import { join, resolve, relative } from "node:path";
import { fileURLToPath } from "node:url";

export const buildOptions = ["-b", "-v", "-o", "record_proofs=1"];
export const auditSessions = ["ERC_TRUST"];
const sha = (value) => createHash("sha256").update(value).digest("hex");
const json = (path) => JSON.parse(readFileSync(path, "utf8"));
const output = (key, value) => appendFileSync(process.env.GITHUB_OUTPUT, `${key}=${value}\n`);

export function files(root) {
  return readdirSync(root).sort().flatMap((name) => {
    const path = join(root, name);
    const stat = lstatSync(path);
    assert(!stat.isSymbolicLink(), `Symlink in state: ${path}`);
    if (stat.isDirectory()) return files(path);
    assert(stat.isFile(), `Non-regular state file: ${path}`);
    return [path];
  });
}

async function digest(path) {
  const hash = createHash("sha256");
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest("hex");
}

export function profileIdentity(env, osRelease, driver) {
  const pins = {};
  for (const name of ["ISABELLE_SHA256", "AFP_ADS_FUNCTOR_SHA256", "FORMAL_FOUNDATION_COMMIT", "ML_SYSTEM", "ISABELLE_PLATFORM64", "RUNNER_OS", "RUNNER_ARCH"]) {
    assert(env[name], `Missing profile input: ${name}`);
    pins[name] = env[name];
  }
  return sha(JSON.stringify({ schema: 1, pins, osRelease, buildOptions, driver }));
}

export async function sourceIdentity(root) {
  const names = execFileSync("git", ["ls-files", "-z"], { cwd: root, encoding: "utf8" }).split("\0").filter(Boolean).sort();
  assert(names.length > 0, "Empty source inventory");
  // A conservative complete tree fingerprint binds generated inputs and consumers.
  // Different source keys may reuse main state only through native freshness checks.
  return sha(JSON.stringify(await Promise.all(names.map(async (name) => [name, await digest(join(root, name))]))));
}

export function checkCatalog(root) {
  const sessions = files(join(root, "formal/isabelle")).filter((path) => /[/\\]ROOT$/.test(path))
    .flatMap((path) => [...readFileSync(path, "utf8").matchAll(/^\s*session\s+(?:"([^"]+)"|([^\s=]+))/gm)].map((m) => m[1] || m[2])).sort();
  assert.deepEqual(sessions, [...auditSessions].sort(), "Every declared session needs an export audit");
  return sessions;
}

export function scanSources(roots) {
  const theories = roots.flatMap(files).filter((path) => path.endsWith(".thy"));
  assert(theories.length > 0, "No proof sources found");
  const forbidden = /^\s*(sorry|oops|axiomatization|oracle)\b|\bby\s+eval\b|\bnative_decide\b|\bskip_proof\b|\bsledgehammer\b|\bsmt_oracle\b/m;
  for (const path of theories) assert(!forbidden.test(readFileSync(path, "utf8")), `Untrusted proof form: ${path}`);
}

export function auditExport(root) {
  const reports = files(root).filter((path) => /[/\\]model-proof-trust\.txt$/.test(path));
  assert.equal(reports.length, 1, "Expected exactly one current proof audit export");
  const entries = readFileSync(reports[0], "utf8").trim().split(/\r?\n/).map((line) => line.split("="));
  assert(entries.every((pair) => pair.length === 2), "Malformed audit report");
  const report = Object.fromEntries(entries);
  assert.equal(entries.length, 4, "Duplicate or unexpected audit fields");
  assert.deepEqual(Object.keys(report).sort(), ["explicit_root_count", "oracle_dependency_count", "qualified_fact_count", "status"]);
  assert.equal(report.status, "PASS");
  assert.equal(report.oracle_dependency_count, "0");
  for (const key of ["explicit_root_count", "qualified_fact_count"]) assert(/^[1-9][0-9]*$/.test(report[key]), `Empty audit: ${key}`);
  return report;
}

export function requireSuccess(gate, formal) {
  assert.equal(gate, "success", "Proof policy checks did not succeed");
  assert.equal(formal, "success", "Native build and export audit did not succeed");
}

export async function seal(state, heaps, identity, env) {
  mkdirSync(state, { recursive: true });
  cpSync(heaps, join(state, "heaps"), { recursive: true });
  const inventory = await Promise.all(files(join(state, "heaps")).map(async (path) => [relative(state, path).replaceAll("\\", "/"), await digest(path)]));
  assert(inventory.some(([name]) => name.endsWith("/ERC_TRUST")), "Missing target heap");
  assert(inventory.some(([name]) => name.endsWith("/log/ERC_TRUST.db")), "Missing target session database");
  const receipt = { schema: 1, ...identity, repository: env.GITHUB_REPOSITORY,
    run: env.GITHUB_RUN_ID, attempt: env.GITHUB_RUN_ATTEMPT, event: env.GITHUB_EVENT_NAME,
    ref: env.GITHUB_REF, commit: env.GITHUB_SHA, inventory };
  writeFileSync(join(state, "receipt.json"), JSON.stringify(receipt, null, 2) + "\n");
}

export async function validateState(state, identity, repository, origin = "main", run = "") {
  assert(/^[0-9a-f]{64}$/.test(identity.profile) && /^[0-9a-f]{64}$/.test(identity.source), "Invalid current identity");
  const receipt = json(join(state, "receipt.json"));
  assert.equal(receipt.schema, 1);
  assert.equal(receipt.profile, identity.profile, "Incompatible tool, dependency, OS or build options");
  assert.equal(receipt.repository, repository, "Foreign repository state");
  assert(/^[0-9a-f]{40}$/.test(receipt.commit) && /^[1-9][0-9]*$/.test(receipt.run) && /^[1-9][0-9]*$/.test(receipt.attempt), "Incomplete execution provenance");
  assert(/^[0-9a-f]{64}$/.test(receipt.source), "Missing source identity");
  if (origin === "pr") {
    assert.equal(receipt.source, identity.source, "PR artifact source differs from merged source");
    assert.equal(receipt.event, "pull_request");
    assert.equal(receipt.run, run, "Artifact belongs to another run");
  } else {
    assert.equal(receipt.event, "push");
    assert.equal(receipt.ref, "refs/heads/main", "Only main writes shared state");
  }
  const actual = await Promise.all(files(join(state, "heaps")).map(async (path) => [relative(state, path).replaceAll("\\", "/"), await digest(path)]));
  assert.deepEqual(receipt.inventory, actual, "State inventory or integrity mismatch");
  assert(actual.some(([name]) => name.endsWith("/ERC_TRUST")), "Missing target heap");
  assert(actual.some(([name]) => name.endsWith("/log/ERC_TRUST.db")), "Missing target session database");
  return receipt;
}

export function eligibleRun(run, pr, repository) {
  // GitHub may empty this supplemental list after merge. The caller binds the
  // commit to the merged PR, and the exact head/repository checks remain below.
  const linkedPr = Array.isArray(run.pull_requests) &&
    (run.pull_requests.length === 0 || run.pull_requests.some((item) => item.number === pr.number));
  return pr.merged === true && pr.base?.ref === "main" && pr.base?.repo?.full_name === repository &&
    pr.head?.repo?.full_name === repository && ["OWNER", "MEMBER", "COLLABORATOR"].includes(pr.author_association) &&
    run.event === "pull_request" && run.status === "completed" && run.conclusion === "success" &&
    run.path === ".github/workflows/proofs.yml" && run.repository?.full_name === repository &&
    run.head_repository?.full_name === repository && run.head_sha === pr.head.sha &&
    linkedPr;
}

export async function selectPrArtifact(api, repository, commit, identity) {
  const prefix = `/repos/${repository}`;
  const pulls = await api(`${prefix}/commits/${commit}/pulls?per_page=100`);
  for (const link of pulls) {
    const pr = await api(`${prefix}/pulls/${link.number}`);
    if (!pr.merged || pr.merge_commit_sha !== commit || pr.head?.repo?.full_name !== repository) continue;
    const { workflow_runs: runs } = await api(`${prefix}/actions/workflows/proofs.yml/runs?event=pull_request&status=success&head_sha=${pr.head.sha}&per_page=10`);
    for (const run of runs) {
      if (!eligibleRun(run, pr, repository)) continue;
      const permission = await api(`${prefix}/collaborators/${encodeURIComponent(run.actor.login)}/permission`);
      if (!["admin", "maintain", "write"].includes(permission.permission)) continue;
      const name = `isabelle-state-${identity.profile}-${identity.source}-${run.run_attempt}`;
      const { artifacts } = await api(`${prefix}/actions/runs/${run.id}/artifacts?per_page=100`);
      const artifact = artifacts.find((item) => item.name === name && !item.expired && item.workflow_run?.id === run.id);
      if (artifact) return { run: String(run.id), artifact: String(artifact.id) };
    }
  }
  return null;
}

async function main([command, ...args]) {
  if (command === "identity") {
    const root = process.cwd();
    checkCatalog(root);
    const driver = [".github/workflows/proofs.yml", "scripts/proof-ci.mjs", "scripts/run-proof-ci.sh", "scripts/test-proof-ci.mjs", "scripts/verify-formal-foundation-supersession.mjs", "formal-dependencies-public-v1.lock.json", "formal-dependencies.lock.json"].map((path) => [path, sha(readFileSync(path))]);
    const identity = { profile: profileIdentity(process.env, readFileSync("/etc/os-release", "utf8"), driver), source: await sourceIdentity(root) };
    writeFileSync(args[0], JSON.stringify(identity));
    for (const [key, value] of Object.entries(identity)) output(key, value);
  } else if (command === "scan") scanSources(args);
  else if (command === "audit") console.log(JSON.stringify(auditExport(args[0])));
  else if (command === "require") requireSuccess(...args);
  else if (command === "seal") await seal(args[0], args[1], json(args[2]), process.env);
  else if (command === "restore") {
    // Validation failures fall back to a normal native build. If an I/O error
    // leaves a partial destination, the final assertion stops before building.
    for (const [state, origin, run] of [[args[0], "pr", args[4]], [args[1], "main", ""]]) {
      if (!existsSync(join(state, "receipt.json"))) continue;
      try {
        await validateState(state, json(args[3]), process.env.GITHUB_REPOSITORY, origin, run);
        assert(!existsSync(args[2]), "Heap destination must be fresh");
        cpSync(join(state, "heaps"), args[2], { recursive: true });
        console.log(`Restored verified ${origin} state; native build and export audit remain mandatory`);
        return;
      } catch (error) { console.log(`State unavailable for reuse: ${error.message}`); }
    }
    assert(!existsSync(args[2]), "Partial restore must not be used");
    console.log("No valid state; native build will calculate missing sessions");
  } else if (command === "select-pr") {
    try {
      const api = async (path) => {
        const response = await fetch(`https://api.github.com${path}`, { headers: { Authorization: `Bearer ${process.env.GITHUB_TOKEN}`, Accept: "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28" }, signal: AbortSignal.timeout(15000) });
        assert(response.ok, `GitHub lookup unavailable (${response.status})`);
        return response.json();
      };
      const selected = await selectPrArtifact(api, process.env.GITHUB_REPOSITORY, process.env.GITHUB_SHA, json(args[0]));
      if (selected) for (const [key, value] of Object.entries(selected)) output(key, value);
      else console.log("No eligible merged-PR artifact; using main cache or normal build");
    } catch (error) { console.log(`PR reuse unavailable: ${error.message}`); }
  } else throw new Error(`Unknown command: ${command}`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).catch((error) => { console.error(error.message); process.exitCode = 1; });
}
