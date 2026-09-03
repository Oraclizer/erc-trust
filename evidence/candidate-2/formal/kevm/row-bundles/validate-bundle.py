#!/usr/bin/env python3
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: validate-bundle.py BUNDLE_JSON")
    root = Path(__file__).resolve().parent
    schema = json.loads((root / "schema.json").read_text(encoding="utf-8"))
    bundle = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    errors = sorted(
        Draft202012Validator(schema).iter_errors(bundle),
        key=lambda error: tuple(str(part) for part in error.absolute_path),
    )
    if errors:
        print(json.dumps({
            "status": "FAIL",
            "errors": [
                {
                    "path": "/" + "/".join(str(part) for part in error.absolute_path),
                    "message": error.message,
                }
                for error in errors
            ],
        }, indent=2))
        raise SystemExit(1)
    print(json.dumps({
        "status": "PASS",
        "obligationId": bundle["obligationId"],
        "schemaVersion": bundle["schemaVersion"],
    }, indent=2))


if __name__ == "__main__":
    main()
