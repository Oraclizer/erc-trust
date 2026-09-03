#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository-root", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    root = args.repository_root.resolve()
    report_path = args.report.resolve()
    report_path.relative_to(root)
    report = json.loads(report_path.read_text(encoding="utf-8"))

    checked: list[str] = []

    def walk(value: object) -> None:
        if isinstance(value, dict):
            if set(("path", "sha256")).issubset(value):
                path = (root / str(value["path"])).resolve()
                path.relative_to(root)
                if not path.is_file():
                    raise SystemExit(f"curated evidence path is missing: {path}")
                actual = sha256(path)
                if actual != value["sha256"]:
                    raise SystemExit(f"curated evidence SHA-256 mismatch: {path}")
                checked.append(path.relative_to(root).as_posix())
            for child in value.values():
                walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)

    walk(report)
    runner_path = (root / report["runner"]["path"]).resolve()
    if sha256(runner_path) != report["runner"]["sourceSha256"]:
        raise SystemExit("runner source SHA-256 mismatch")
    positive = report["positive"]["analysis"]["graph"]
    negative = report["negative"]["analysis"]["graph"]
    if any(positive[key] != 0 for key in ("terminal", "stuck", "vacuous", "pending")):
        raise SystemExit("positive curated graph is not theorem-grade closed")
    if positive["admitted"] is not False:
        raise SystemExit("positive curated proof is admitted")
    if negative["terminal"] != 1 or negative["stuck"] != 0 or negative["vacuous"] != 0:
        raise SystemExit("negative curated graph lacks the exact semantic counterexample shape")
    terminal_path = root / report["negative"]["terminalWitness"]["path"]
    terminal_text = terminal_path.read_text(encoding="utf-8")
    for token in report["negative"]["terminalWitness"]["tokens"]:
        if token not in terminal_text:
            raise SystemExit(f"curated terminal witness token is missing: {token}")
    if report["isabelle"]["oracleDependencyCount"] != 0:
        raise SystemExit("curated Isabelle closure has oracle dependencies")
    if report["status"] == "PASS":
        if report["authoritativeFreshReplayRequired"]:
            raise SystemExit("PASS report cannot require another authoritative fresh replay")
        if report["runner"]["sourceSha256"] != report["runner"]["executedSha256"]:
            raise SystemExit("PASS report runner source does not equal the executed runner")
    elif report["status"] != "WORKER_REPLAY_CANDIDATE":
        raise SystemExit(f"unsupported curated report status: {report['status']}")

    print(json.dumps({
        "status": "PASS",
        "reportStatus": report["status"],
        "obligationId": report["obligationId"],
        "checkedRepositoryArtifacts": len(set(checked)),
        "reportSha256": sha256(report_path),
    }, indent=2))


if __name__ == "__main__":
    main()
