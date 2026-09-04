// SPDX-License-Identifier: BSD-3-Clause
//
// Link, heading-anchor, and path check for every Markdown file in the tree.
//
// Every link is classified before it is checked. Inline links, reference-style link
// definitions, autolinks, and the src and href attributes of raw HTML are all collected.
//   repository   a relative target that must exist in the tree (with its heading anchor, if any)
//   eip          a `./eip-NNNN.md` or `./erc-NNNN.md` target, valid only inside the proposal text,
//                where it resolves in the ethereum/ERCs tree rather than in this one; normative
//                dependencies must appear in `requires`, while the reviewed related-work set below
//                may be linked without becoming a dependency
//   external     an http(s) target, whose host must be on the allowlist below; the allowlist is
//                kept to the hosts the tree actually links, so a new host is a reviewed change
//   mailto       a mailto: target
// Path spans must name a file or directory that exists, so that a moved or deleted artifact
// cannot survive in the prose: a backtick span, or a whitespace-delimited token inside a fenced
// code block, that starts with a tracked top-level directory and has at least one more segment.
// The preserved candidate 2 history under evidence/candidate-2/ is kept byte for byte and
// describes paths as they were at the time, so its path spans are not checked; its links are.

import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, extname, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const excluded = new Set([".git", ".certora_internal", ".kontrol", "cache", "dist", "kout", "node_modules", "out"]);
const externalHosts = new Set(["arxiv.org", "creativecommons.org", "github.com", "img.shields.io", "isa-afp.org", "logicalhacking.com", "prover.certora.com", "www.contributor-covenant.org"]);
const proposalFile = "docs/ERC-DRAFT.md";
const requiredEips = new Set(["20", "165", "7943", "8319"]);
const relatedWorkEips = new Set(["1450", "3643"]);
const historyRoots = ["evidence/candidate-2/"];
const pathSegmentsNotInTree = new Set(["node_modules", "out", "cache", "kout", "dist"]);
const report = process.argv.includes("--report");
const failures = [];
const counts = { repository: 0, eip: 0, external: 0, mailto: 0, pathSpans: 0 };
const hosts = new Map();

function walk(path) {
  const rel = relative(root, path).replaceAll("\\", "/");
  if (rel && rel.split("/").some((part) => excluded.has(part))) return [];
  if (statSync(path).isFile()) return extname(path).toLowerCase() === ".md" ? [path] : [];
  return readdirSync(path)
    .sort()
    .flatMap((entry) => walk(resolve(path, entry)));
}

// Heading text may carry inline HTML; every tag is removed, repeatedly until nothing changes,
// so that no partial tag survives a single pass, and the anchor is then built from the text.
function stripTags(text) {
  let current = text;
  for (;;) {
    const next = current.replace(/<[^>]*>/g, "");
    if (next === current) return current.replace(/[<>]/g, "");
    current = next;
  }
}

function anchorsFor(path) {
  const seen = new Map();
  const anchors = new Set();
  for (const line of readFileSync(path, "utf8").split(/\r?\n/)) {
    const match = /^(#{1,6})\s+(.+?)\s*$/.exec(line);
    if (!match) continue;
    const base = stripTags(match[2])
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

function requiresOf(text) {
  const preamble = /^---\n([\s\S]*?)\n---\n/.exec(text);
  const line = preamble ? /^requires:\s*(.+)$/m.exec(preamble[1]) : null;
  return new Set(line ? line[1].split(",").map((item) => item.trim()) : []);
}

const topLevel = new Set(readdirSync(root).filter((entry) => !excluded.has(entry) && statSync(resolve(root, entry)).isDirectory()));
const markdownFiles = walk(root);
const anchorCache = new Map();
const pathPattern = /^[A-Za-z0-9_.-]+(\/[A-Za-z0-9_.-]+)+\/?$/;

function checkPathSpan(source, sourceRel, span) {
  if (!pathPattern.test(span)) return;
  const segments = span.replace(/\/$/, "").split("/");
  if (!topLevel.has(segments[0])) return;
  if (segments.some((segment) => pathSegmentsNotInTree.has(segment))) return;
  counts.pathSpans += 1;
  if (!existsSync(resolve(root, span)) && !existsSync(resolve(dirname(source), span))) {
    failures.push(`path does not exist: ${sourceRel} -> \`${span}\``);
  }
}

for (const source of markdownFiles) {
  const sourceRel = relative(root, source).replaceAll("\\", "/");
  const text = readFileSync(source, "utf8");
  const fences = [...text.matchAll(/```[\s\S]*?```/g)].map((match) => match[0]);
  const withoutFences = text.replace(/```[\s\S]*?```/g, "");
  const requires = sourceRel === proposalFile ? requiresOf(text) : null;
  if (requires && JSON.stringify([...requires].sort()) !== JSON.stringify([...requiredEips].sort())) {
    failures.push(`proposal requires drift: expected ${[...requiredEips].join(", ")}`);
  }

  const targets = [];
  for (const match of withoutFences.matchAll(/!?\[[^\]]*]\(([^)\s]+)(?:\s+"[^"]*")?\)/g)) targets.push(match[1]);
  for (const match of withoutFences.matchAll(/^\s*\[[^\]]+]:\s*(\S+)/gm)) targets.push(match[1]);
  for (const match of withoutFences.matchAll(/<(https?:[^>\s]+)>/g)) targets.push(match[1]);
  for (const match of withoutFences.matchAll(/\s(?:src|href)=["']([^"']+)["']/g)) targets.push(match[1]);

  for (const rawTarget of targets) {
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
    if (/^#/.test(rawTarget)) {
      const anchors = anchorCache.get(source) ?? anchorsFor(source);
      anchorCache.set(source, anchors);
      if (!anchors.has(decodeURIComponent(rawTarget.slice(1)).toLowerCase())) failures.push(`missing heading anchor: ${label}`);
      continue;
    }
    const [rawPath, rawFragment = ""] = rawTarget.split("#", 2);
    const eip = /^\.\/(?:eip|erc)-(\d+)\.md$/i.exec(rawPath);
    if (eip) {
      counts.eip += 1;
      if (sourceRel !== proposalFile) failures.push(`EIP repository link outside the proposal text: ${label}`);
      else if (!requires.has(eip[1]) && !relatedWorkEips.has(eip[1])) {
        failures.push(`EIP repository link is neither a required dependency nor reviewed related work: ${label}`);
      }
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
  for (const match of withoutFences.matchAll(/`([^`\n]+)`/g)) checkPathSpan(source, sourceRel, match[1].trim());
  for (const fence of fences) {
    for (const token of fence.replace(/^```[^\n]*\n|```$/g, "").split(/\s+/)) checkPathSpan(source, sourceRel, token.replace(/^["'(]+|["'),;]+$/g, ""));
  }
}

if (report) {
  console.log(JSON.stringify({ markdownFiles: markdownFiles.length, counts, hosts: Object.fromEntries([...hosts.entries()].sort()) }, null, 2));
}
if (failures.length) {
  for (const failure of failures) console.error(failure);
  process.exit(1);
}
console.log(`link, anchor, and path PASS: ${markdownFiles.length} Markdown files; ${counts.repository} repository links, ${counts.eip} EIP repository links, ${counts.external} external links on ${hosts.size} allowlisted hosts, ${counts.mailto} mailto links, ${counts.pathSpans} path spans`);
