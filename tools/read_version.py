#!/usr/bin/env python3
"""Print a single KEY=value from tools/versions.env for Makefile includes."""

from __future__ import annotations

import sys
from pathlib import Path

VERSIONS_FILE = Path(__file__).resolve().parent / "versions.env"


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: read_version.py KEY", file=sys.stderr)
        return 1

    key = sys.argv[1]
    for line in VERSIONS_FILE.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        line_key, value = stripped.split("=", 1)
        if line_key.strip() == key:
            print(value.strip())
            return 0

    print(f"{key} not found in {VERSIONS_FILE}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
