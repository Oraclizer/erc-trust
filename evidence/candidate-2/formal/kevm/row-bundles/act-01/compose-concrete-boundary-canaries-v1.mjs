// Compose already generated concrete boundary canaries into one K module so
// the fixed parser cost is paid once per segment family. This is diagnostic
// infrastructure only; composing source claims is not a theorem that their
// intermediate states agree.
import { createHash } from "node:crypto";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

const values = (flag) => process.argv
  .map((value, index) => value === flag ? process.argv[index + 1] : undefined)
  .filter(Boolean);
const value = (flag) => values(flag).at(-1);
const inputs = values("--input");
const moduleName = value("--module");
const output = value("--output");
if (inputs.length < 2 || !moduleName || !output) {
  throw new Error("usage: node compose-concrete-boundary-canaries-v1.mjs --input FILE --input FILE [--input FILE ...] --module MODULE --output ABSENT_FILE");
}
if (!/^[A-Z][A-Z0-9-]*$/.test(moduleName)) throw new Error("module must use K module syntax");
if (existsSync(output)) throw new Error(`output already exists: ${output}`);

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
const claims = inputs.map((input) => {
  const path = resolve(input);
  const source = readFileSync(path, "utf8");
  if (!source.startsWith('requires "../../trust-runtime-verification.k"')) {
    throw new Error(`unexpected requires line: ${path}`);
  }
  const match = source.match(/\n(  claim\n[\s\S]*?)\n\nendmodule\s*$/);
  if (!match) throw new Error(`claim body is absent: ${path}`);
  return { path, sha256: sha256(Buffer.from(source, "utf8")), body: match[1] };
});

const composed = `requires "../../trust-runtime-verification.k"

// Diagnostic-only family batch. Each claim remains an independent positive
// topology canary. Row credit additionally requires universalization,
// negative reach, explicit intermediate-state composition, a row corollary,
// an approved TCB profile, and independent replay.
module ${moduleName}
  imports TRUST-RUNTIME-VERIFICATION

${claims.map(({ body }) => body).join("\n\n")}

endmodule
`;
writeFileSync(resolve(output), composed);
process.stdout.write(`${JSON.stringify({
  status: "PASS_COMPOSED_DIAGNOSTIC_ONLY",
  module: moduleName,
  claimCount: claims.length,
  inputs: claims.map(({ path, sha256: hash }) => ({ path, sha256: hash })),
  outputSha256: sha256(Buffer.from(composed, "utf8")),
})}\n`);
