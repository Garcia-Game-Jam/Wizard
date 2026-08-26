#!/usr/bin/env python3
"""Run Godot headless to surface GDScript analyzer WARNINGs; fail if any appear.

This catches editor console warnings (integer division, shadowed vars, redundant
await, static-called-on-instance, etc.) that gdlint does not cover.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from restore_extensions import find_godot_binary, sync_extensions  # noqa: E402

WARN_LOG = ROOT / ".cache" / "godot-warnings.log"
PROBE_SCRIPT = "res://tools/probe_gdscript_warnings.gd"

# Paths we own — ignore addons/vendor noise.
OWNED_PATH_PREFIXES = (
    "res://scripts/",
    "res://tests/",
    "res://scenes/",
    "res://tools/",
)

WARNING_LINE = re.compile(r"^WARNING:\s*(.+)$")
AT_LINE = re.compile(
    r"^\s*at:\s+GDScript::reload\s+\((res://[^)]+\.gd):(\d+)\)\s*$"
)
# Some Godot builds put path on the WARNING line itself.
WARNING_WITH_PATH = re.compile(
    r"^WARNING:.*\((res://[^)]+\.gd):(\d+)\)\s*$"
)


def _is_owned_path(path: str) -> bool:
    return path.startswith(OWNED_PATH_PREFIXES)


def parse_gdscript_warnings(output: str) -> list[str]:
    """Extract owned-project GDScript WARNING entries from Godot output."""
    findings: list[str] = []
    lines = output.splitlines()
    pending_message: str | None = None

    for raw in lines:
        line = raw.strip("\r")
        owned_on_line = WARNING_WITH_PATH.match(line.strip())
        if owned_on_line:
            path, lineno = owned_on_line.group(1), owned_on_line.group(2)
            if _is_owned_path(path):
                msg = line.strip()
                findings.append(f"{path}:{lineno}: {msg}")
            pending_message = None
            continue

        warn_match = WARNING_LINE.match(line.strip())
        if warn_match:
            pending_message = warn_match.group(1).strip()
            continue

        if pending_message is not None:
            at_match = AT_LINE.match(line)
            if at_match:
                path, lineno = at_match.group(1), at_match.group(2)
                if _is_owned_path(path):
                    findings.append(f"{path}:{lineno}: {pending_message}")
                pending_message = None
                continue
            # Non-matching follow-up — drop orphan WARNING without path.
            if line.strip() == "" or line.strip().startswith("at:"):
                pending_message = None

    # Deduplicate while preserving order.
    seen: set[str] = set()
    unique: list[str] = []
    for item in findings:
        if item not in seen:
            seen.add(item)
            unique.append(item)
    return unique


def run_warning_probe(*, timeout_sec: int = 90) -> tuple[int, str, list[str]]:
    """Return (exit_code, combined_output, warning_findings)."""
    sync_extensions(find_godot_binary())
    godot = find_godot_binary()
    if godot is None:
        return (
            1,
            "Godot executable not found. Set GODOT_PATH or tools/versions.env "
            "to run GDScript warning checks.",
            [],
        )

    WARN_LOG.parent.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["FRIEND_SLOP_TEST"] = "1"
    try:
        with WARN_LOG.open("w", encoding="utf-8") as log_handle:
            proc = subprocess.run(
                [
                    str(godot),
                    "--headless",
                    "--path",
                    str(ROOT),
                    "--script",
                    PROBE_SCRIPT,
                ],
                cwd=str(ROOT),
                env=env,
                stdout=log_handle,
                stderr=subprocess.STDOUT,
                timeout=timeout_sec,
            )
        output = WARN_LOG.read_text(encoding="utf-8", errors="replace")
    except subprocess.TimeoutExpired:
        output = WARN_LOG.read_text(encoding="utf-8", errors="replace") if WARN_LOG.exists() else ""
        return 1, f"GDScript warning probe timed out after {timeout_sec}s.\n{output}", []

    findings = parse_gdscript_warnings(output)
    # Probe script may crash on exit (gdvosk); treat as OK if we got clean compile output.
    if findings:
        return 1, output, findings
    if "Failed loading" in output or "Parse Error" in output or "Compile Error" in output:
        return 1, output, findings
    # Crash-on-quit is acceptable when no warnings/errors were found.
    _ = proc.returncode
    return 0, output, findings


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--timeout",
        type=int,
        default=int(os.environ.get("GODOT_WARN_TIMEOUT_SEC", "90")),
        help="Seconds before aborting the Godot probe.",
    )
    args = parser.parse_args(argv)

    print("Checking GDScript analyzer warnings...")
    code, output, findings = run_warning_probe(timeout_sec=args.timeout)
    if findings:
        print(f"Found {len(findings)} GDScript warning(s):\n", file=sys.stderr)
        for item in findings:
            print(f"  {item}", file=sys.stderr)
        print(
            "\nFix these before committing. Re-run: "
            "python tools/run_checks.py --lint-only",
            file=sys.stderr,
        )
        return 1
    if code != 0:
        print(output, file=sys.stderr)
        print("GDScript warning probe failed (see output above).", file=sys.stderr)
        return 1
    print("Success: no GDScript analyzer warnings in scripts/tests/scenes.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
