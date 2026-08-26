#!/usr/bin/env python3
"""Fail if workflow pins drift from tools/versions.env."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VERSIONS_FILE = ROOT / "tools" / "versions.env"
WORKFLOWS_DIR = ROOT / ".github" / "workflows"


def _load_versions() -> dict[str, str]:
    versions: dict[str, str] = {}
    for line in VERSIONS_FILE.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, value = stripped.split("=", 1)
        versions[key.strip()] = value.strip()
    return versions


def main() -> int:
    versions = _load_versions()
    godot_version = versions.get("GODOT_VERSION", "")
    if not godot_version:
        print("GODOT_VERSION missing from tools/versions.env", file=sys.stderr)
        return 1

    errors: list[str] = []
    for workflow in sorted(WORKFLOWS_DIR.glob("*.yml")):
        text = workflow.read_text(encoding="utf-8")
        for match in re.finditer(r"GODOT_VERSION:\s*\"?([^\"\n]+)\"?", text):
            found = match.group(1).strip()
            if found != godot_version:
                errors.append(
                    f"{workflow.relative_to(ROOT)}: GODOT_VERSION is {found!r}, "
                    f"expected {godot_version!r} from tools/versions.env"
                )
        for match in re.finditer(r"barichello/godot-ci:([0-9.]+)", text):
            found = match.group(1).strip()
            if found != godot_version:
                errors.append(
                    f"{workflow.relative_to(ROOT)}: godot-ci image tag is {found!r}, "
                    f"expected {godot_version!r} from tools/versions.env"
                )

    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1

    print(f"Pinned versions OK (Godot {godot_version})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
