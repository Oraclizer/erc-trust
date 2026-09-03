// SPDX-License-Identifier: BSD-3-Clause
//
// Link, heading-anchor, and path check for every Markdown file in the tree.
//
// Every Markdown link is classified before it is checked:
//   repository   a relative target that must exist in the tree (with its heading anchor, if any)
//   eip          a `./eip-NNNN.md` or `./erc-NNNN.md` target, valid only inside the proposal text,
//                where it resolves in the ethereum/ERCs tree rather than in this one
//   external     an http(s) target, whose host must be on the allowlist below
//   mailto       a mailto: target
// Backtick spans that name a repository path (a tracked top-level directory followed by at
// least one path segment) must name a file or directory that exists, so that a moved or
// deleted artifact cannot survive in the prose. The preserved candidate 2 history under
// evidence/candidate-2/ is kept byte for byte and describes paths as they were at the time,
// so its backtick paths are not checked; its links still are.

import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, extname, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const excluded = new Set([".git", ".certora_internal", ".kontrol", "cache", "dist", "kout", "node_modules", "out"]);
const externalHosts = new Set([
  "arxiv.org",
  "doi.org",
  "eips.ethereum.org",
  "ethereum-magicians.org",
  "ethresear.ch",
  "github.com",
  "img.shields.io",
  "isa-afp.org",
  "logicalhacking.com",
  "orcid.org",
  "prover.certora.com",
  "www.isa-afp.org",
]);
const eipRepositoryFiles = new Set(["docs/ERC-DRAFT.md"]);
const historyRoots = ["evidence/candidate-2/"];
const pathSegmentsNotInTree = new Set(["node_modules", "out", "cache", "kout", "dist"]);
const report = process.argv.includes("--report");
const failures = [];
const counts = { repository: 0, eip: 0, external: 0, mailto: 0, backtickPaths: 0 };
const hosts = new Map();

function walk(path) {
  const rel = relative(root, path).replaceAll("\\", "/");
  if (rel && rel.split("/").some((part) => excluded.has(part))) return [];
  if (statSync(path).isFile()) return extname(path).toLowerCase() === ".md" ? [path] : [];
  return readdirSync(path)
    .sort()
    .flatMap((entry) => walk(resolve(path, entry)));
}

function anchorsFor(path) {
  const seen = new Map();
  const anchors = new Set();
  for (const line of readFileSync(path, "utf8").split(/\r?\n/)) {
    const match = /^(#{1,6})\s+(.+?)\s*$/.exec(line);
    if (!match) continue;
    const base = match[2]
      .replace(/<[^>]*>/g, "")
      .replace(/[`*_~]/g, "")
      .toLowerCase()
      .replace(/[^\p{L}\p{N}\s-]/gu, "")
      .trim()
      .replace(/\s+/g, "-");
    const duplicate = seen.get(base) ?? 0;
    seen.set(base, duplicate + 1);
    anchors.add(duplicate === 0 ? base : `${base}-${duplicate}`);
  }
  return anchors;
}

const topLevel = new Set(readdirSync(root).filter((entry) => !excluded.has(entry) && statSync(resolve(root, entry)).isDirectory()));
const markdownFiles = walk(root);
const anchorCache = new Map();

for (const source of markdownFiles) {
  const sourceRel = relative(root, source).replaceAll("\\", "/");
  const text = readFileSync(source, "utf8");
  const withoutFences = text.replace(/```[\s\S]*?```/g, "");

  for (const match of withoutFences.matchAll(/!?\[[^\]]*]\(([^)\s]+)(?:\s+"[^"]*")?\)/g)) {
    const rawTarget = match[1];
    const label = `${sourceRel} -> ${rawTarget}`;
    if (/^mailto:/i.test(rawTarget)) { counts.mailto += 1; continue; }
    if (/^https?:/i.test(rawTarget)) {
      counts.external += 1;
      let host;
      try { host = new URL(rawTarget).hostname.toLowerCase(); } catch { failures.push(`malformed external link: ${label}`); continue; }
      hosts.set(host, (hosts.get(host) ?? 0) + 1);
      if (!externalHosts.has(host)) failures.push(`external link host not on the allowlist: ${label}`);
      continue;
    }
    const [rawPath, rawFragment = ""] = rawTarget.split("#", 2);
    if (/^\.\/(eip|erc)-\d+\.md$/i.test(rawPath)) {
      counts.eip += 1;
      if (!eipRepositoryFiles.has(sourceRel)) failures.push(`EIP repository link outside the proposal text: ${label}`);
      continue;
    }
    counts.repository += 1;
    const decodedPath = decodeURIComponent(rawPath);
    const target = decodedPath ? resolve(dirname(source), decodedPath) : source;
    if (!existsSync(target)) { failures.push(`missing link target: ${label}`); continue; }
    if (rawFragment && statSync(target).isFile() && extname(target).toLowerCase() === ".md") {
      const anchors = anchorCache.get(target) ?? anchorsFor(target);
      anchorCache.set(target, anchors);
      if (!anchors.has(decodeURIComponent(rawFragment).toLowerCase())) failures.push(`missing heading anchor: ${label}`);
    }
  }

  if (historyRoots.some((prefix) => sourceRel.startsWith(prefix))) continue;
  for (const match of withoutFences.matchAll(/`([^`\n]+)`/g)) {
    const span = match[1].trim();
    if (!/^[A-Za-z0-9_.-]+(\/[A-Za-z0-9_.-]+)+\/?$/.test(span)) continue;
    const segments = span.replace(/\/$/, "").split("/");
    if (!topLevel.has(segments[0])) continue;
    if (segments.some((segment) => pathSegmentsNotInTree.has(segment))) continue;
    counts.backtickPaths += 1;
    const fromRoot = resolve(root, span);
    const fromSource = resolve(dirname(source), span);
    if (!existsSync(fromRoot) && !existsSync(fromSource)) failures.push(`backtick path does not exist: ${sourceRel} -> \`${span}\``);
  }
}

if (report) {
  console.log(JSON.stringify({ markdownFiles: markdownFiles.length, counts, hosts: Object.fromEntries([...hosts.entries()].sort()) }, null, 2));
}
if (failures.length) {
  for (const failure of failures) console.error(failure);
  process.exit(1);
}
console.log(`link, anchor, and path PASS: ${markdownFiles.length} Markdown files; ${counts.repository} repository links, ${counts.eip} EIP repository links, ${counts.external} external links on ${hosts.size} allowlisted hosts, ${counts.mailto} mailto links, ${counts.backtickPaths} backtick paths`);
