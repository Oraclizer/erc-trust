// SPDX-License-Identifier: BSD-3-Clause

import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, extname, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const excluded = new Set([
  ".git",
  ".certora_internal",
  ".kontrol",
  "cache",
  "dist",
  "kout",
  "node_modules",
  "out",
]);
const failures = [];

function walk(path) {
  const rel = relative(root, path).replaceAll("\\", "/");
  if (rel && rel.split("/").some((part) => excluded.has(part))) return [];
  if (statSync(path).isFile()) return extname(path).toLowerCase() === ".md" ? [path] : [];
  return readdirSync(path)
    .sort()
    .flatMap((entry) => walk(resolve(path, entry)));
}

function anchorsFor(path) {
  const counts = new Map();
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
    const duplicate = counts.get(base) ?? 0;
    counts.set(base, duplicate + 1);
    anchors.add(duplicate === 0 ? base : `${base}-${duplicate}`);
  }
  return anchors;
}

const markdownFiles = walk(root);
const anchorCache = new Map();
for (const source of markdownFiles) {
  const text = readFileSync(source, "utf8");
  const withoutFences = text.replace(/```[\s\S]*?```/g, "");
  const links = withoutFences.matchAll(/!?\[[^\]]*]\(([^)\s]+)(?:\s+"[^"]*")?\)/g);
  for (const match of links) {
    const rawTarget = match[1];
    if (/^(https?:|mailto:)/i.test(rawTarget)) continue;
    const [rawPath, rawFragment = ""] = rawTarget.split("#", 2);
    const decodedPath = decodeURIComponent(rawPath);
    const target = decodedPath ? resolve(dirname(source), decodedPath) : source;
    const label = `${relative(root, source).replaceAll("\\", "/")} -> ${rawTarget}`;
    if (!existsSync(target)) {
      failures.push(`missing link target: ${label}`);
      continue;
    }
    if (rawFragment && statSync(target).isFile() && extname(target).toLowerCase() === ".md") {
      const anchors = anchorCache.get(target) ?? anchorsFor(target);
      anchorCache.set(target, anchors);
      const fragment = decodeURIComponent(rawFragment).toLowerCase();
      if (!anchors.has(fragment)) failures.push(`missing heading anchor: ${label}`);
    }
  }
}

if (failures.length) {
  for (const failure of failures) console.error(failure);
  process.exit(1);
}
console.log(`link and heading-anchor PASS: ${markdownFiles.length} Markdown files`);
