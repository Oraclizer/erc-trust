import { execFileSync } from "node:child_process";

const versionPattern = /^\d+\.\d+\.\d+$/;
const distributionPattern = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const sha256Pattern = /^[0-9a-f]{64}$/;

export function resolvePinnedSolc(solc) {
  const locator = solc?.binaryLocator;
  if (locator?.kind !== "svm") throw new Error(`unsupported solc locator: ${locator?.kind}`);
  if (!distributionPattern.test(locator.distribution)) {
    throw new Error(`invalid WSL distribution in solc locator: ${locator.distribution}`);
  }
  if (!versionPattern.test(locator.version) || !solc.version.startsWith(`${locator.version}+`)) {
    throw new Error(`invalid solc version locator: ${locator.version}`);
  }
  if (!sha256Pattern.test(solc.binarySha256)) throw new Error("invalid pinned solc SHA-256");

  const resolver = [
    "set -eu",
    'version="$1"',
    'data_root="${XDG_DATA_HOME:-$HOME/.local/share}"',
    'candidate="$data_root/svm/$version/solc-$version"',
    'test -f "$candidate"',
    'test -x "$candidate"',
    'printf "%s\\n" "$candidate"',
  ].join("\n");
  const binaryPath = execFileSync(
    "wsl.exe",
    ["-d", locator.distribution, "-e", "sh", "-c", resolver, "resolve-pinned-solc", locator.version],
    { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
  ).trim();
  if (!/^\/[^\0\r\n]+$/.test(binaryPath)) throw new Error(`invalid resolved solc path: ${binaryPath}`);

  const binarySha256 = execFileSync(
    "wsl.exe",
    ["-d", locator.distribution, "-e", "sha256sum", binaryPath],
    { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
  ).trim().split(/\s+/)[0];
  if (binarySha256 !== solc.binarySha256) {
    throw new Error(`solc binary identity mismatch: ${binarySha256}`);
  }

  const versionOutput = execFileSync(
    "wsl.exe",
    ["-d", locator.distribution, "-e", binaryPath, "--version"],
    { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
  ).trim();
  if (!versionOutput.includes(solc.version)) throw new Error(`solc version mismatch: ${versionOutput}`);

  return { binaryPath, distribution: locator.distribution, versionOutput };
}
