// SPDX-License-Identifier: BSD-3-Clause

import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const oldReportPath = resolve(root, "pilot", "evidence", "proof-report.md");
const newReportPath = resolve(root, "pilot", "evidence", "proof-report-v2.md");
const oldHashesPath = resolve(root, "pilot", "evidence", "hashes.json");
const newHashesPath = resolve(root, "pilot", "evidence", "hashes-v2.json");

const oldReport = readFileSync(oldReportPath, "utf8");
const newReport = oldReport.replaceAll("—", ":").replaceAll("–", "-");
if (newReport.includes("—") || newReport.includes("–")) throw new Error("dash normalization failed");
writeFileSync(newReportPath, newReport, "utf8");

const hashes = JSON.parse(readFileSync(oldHashesPath, "utf8"));
delete hashes.files["pilot/evidence/proof-report.md"];
hashes.schemaVersion = 2;
hashes.supersedes = {
  path: "pilot/evidence/hashes.json",
  sha256: sha256(readFileSync(oldHashesPath)),
  transformation: "The proof report title punctuation was normalized for the public surface; proof claims and evidence values are unchanged.",
};
hashes.files["pilot/evidence/proof-report-v2.md"] = sha256(readFileSync(newReportPath));
writeFileSync(newHashesPath, `${JSON.stringify(hashes, null, 2)}\n`, "utf8");

console.log(JSON.stringify({
  status: "PASS",
  historicalReportSha256: sha256(readFileSync(oldReportPath)),
  publicReportSha256: sha256(readFileSync(newReportPath)),
  historicalManifestSha256: sha256(readFileSync(oldHashesPath)),
  publicManifestSha256: sha256(readFileSync(newHashesPath)),
}, null, 2));
