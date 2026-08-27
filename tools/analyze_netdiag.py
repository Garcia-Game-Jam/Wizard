#!/usr/bin/env python3
"""Summarise NetDiag capture folders (user://diag/<stamp>/).

Usage:
    python tools/analyze_netdiag.py <session_dir> [<session_dir> ...]
    python tools/analyze_netdiag.py --all           # scans the default diag root

Prints a per-session table of percentiles for the frame stream, plus a PASS/FAIL
line against the thresholds in THRESHOLDS. Slice 1 reads frame.csv only; per-pawn
metrics arrive in a later slice.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import sys
from pathlib import Path

# p95 ceilings — deliberately loose for a first baseline, tighten as data lands.
THRESHOLDS = {
    "proc_ms.p99": 20.0,
    "rb_depth.p95": 2.0,
    "tickloop_ms.p99": 6.0,
    "clock_stretch.spread": 0.35,  # p95 - p05
}

DIAG_ROOT_CANDIDATES = (
    Path.home() / "AppData/Roaming/Godot/app_userdata/Wizard/diag",
    Path.home() / ".local/share/godot/app_userdata/Wizard/diag",
    Path.home() / "Library/Application Support/Godot/app_userdata/Wizard/diag",
)


def _percentile(values: list[float], pct: float) -> float:
    if not values:
        return float("nan")
    ordered = sorted(values)
    idx = min(len(ordered) - 1, max(0, round((pct / 100.0) * (len(ordered) - 1))))
    return ordered[idx]


def _load_frames(session: Path) -> list[dict[str, float]]:
    frame_csv = session / "frame.csv"
    if not frame_csv.exists():
        return []
    rows: list[dict[str, float]] = []
    with frame_csv.open(newline="") as handle:
        for raw in csv.DictReader(handle):
            row: dict[str, float] = {}
            for key, value in raw.items():
                try:
                    row[key] = float(value)
                except (TypeError, ValueError):
                    row[key] = float("nan")
            rows.append(row)
    return rows


def _column(rows: list[dict[str, float]], key: str) -> list[float]:
    return [r[key] for r in rows if key in r and r[key] == r[key]]


def _summary(rows: list[dict[str, float]]) -> dict[str, float]:
    proc = _column(rows, "proc_ms")
    phys = _column(rows, "phys_ms")
    tickloop_ms = [v / 1000.0 for v in _column(rows, "tickloop_us")]
    rb = _column(rows, "rb_depth")
    stretch = _column(rows, "clock_stretch")
    fps = _column(rows, "fps")
    return {
        "frames": float(len(rows)),
        "fps.p50": _percentile(fps, 50),
        "proc_ms.p50": _percentile(proc, 50),
        "proc_ms.p99": _percentile(proc, 99),
        "proc_ms.max": max(proc) if proc else float("nan"),
        "phys_ms.p99": _percentile(phys, 99),
        "tickloop_ms.p50": _percentile(tickloop_ms, 50),
        "tickloop_ms.p99": _percentile(tickloop_ms, 99),
        "rb_depth.p50": _percentile(rb, 50),
        "rb_depth.p95": _percentile(rb, 95),
        "rb_depth.max": max(rb) if rb else float("nan"),
        "clock_stretch.spread": _percentile(stretch, 95) - _percentile(stretch, 5),
    }


def _print_session(session: Path) -> bool:
    rows = _load_frames(session)
    meta = {}
    meta_path = session / "meta.json"
    if meta_path.exists():
        meta = json.loads(meta_path.read_text())

    print(f"\n=== {session.name} ===")
    ctx = meta.get("context", {})
    cfg = meta.get("backend_config", {})
    print(f"  backend={meta.get('backend', '?')} role={ctx.get('role', '?')} "
          f"scenario={ctx.get('scenario', '?')}")
    if cfg:
        print("  config: " + " ".join(f"{k}={v}" for k, v in cfg.items()))
    if not rows:
        print("  (no frame.csv rows)")
        return False

    summary = _summary(rows)
    for key, value in summary.items():
        print(f"  {key:24s} {value:10.3f}")

    ok = True
    for key, ceiling in THRESHOLDS.items():
        got = summary.get(key, float("nan"))
        flag = "ok " if got <= ceiling else "OVER"
        if got > ceiling:
            ok = False
        print(f"  [{flag}] {key} = {got:.3f} (<= {ceiling})")
    print(f"  RESULT: {'PASS' if ok else 'FAIL'}")
    return ok


def _resolve_sessions(args: argparse.Namespace) -> list[Path]:
    if args.all:
        for root in DIAG_ROOT_CANDIDATES:
            if root.is_dir():
                return sorted(p for p in root.iterdir() if p.is_dir())
        print("no diag root found; pass explicit folders", file=sys.stderr)
        return []
    return [Path(p) for p in args.sessions]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sessions", nargs="*", help="NetDiag session folders")
    parser.add_argument("--all", action="store_true", help="scan the default diag root")
    args = parser.parse_args()

    sessions = _resolve_sessions(args)
    if not sessions:
        parser.print_help()
        return 2

    all_ok = True
    for session in sessions:
        if not _print_session(session):
            all_ok = False
    return 0 if all_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
