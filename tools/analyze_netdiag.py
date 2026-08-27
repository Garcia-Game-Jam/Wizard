#!/usr/bin/env python3
"""Summarise NetDiag capture folders (user://diag/<stamp>_<role>_<pid>/).

Usage:
    python tools/analyze_netdiag.py <session_dir> [<session_dir> ...]
    python tools/analyze_netdiag.py --all           # scans the default diag root

Reads frame.csv (real per-frame time, rollback depth, tick-loop cost, clock
health), events.csv (named markers) and pawn.csv (per-tick floor state). Prints
percentiles, the worst frames with their nearest marker, and a floor-state check.
PASS/FAIL is against the loose first-pass ceilings in THRESHOLDS.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import sys
from collections import Counter
from pathlib import Path

# p95/max ceilings, loose first pass. Keys are matched as substrings against the
# summary so pawn-specific keys (pawn_1[rem].stuck_airborne_pct) are covered.
THRESHOLDS = {
    "frame_ms.p99": 20.0,
    "frame_ms.max": 50.0,
    "rb_depth.p99": 3.0,
    "tickloop_ms.p99": 6.0,
    "clock_stretch.spread": 0.35,
    "stuck_airborne_pct": 5.0,
    "grounded_vy_abs.p95": 1.0,
    "on_floor_flips": 10.0,
}

DIAG_ROOT_CANDIDATES = (
    Path.home() / "AppData/Roaming/Godot/app_userdata/Wizard/diag",
    Path.home() / ".local/share/godot/app_userdata/Wizard/diag",
    Path.home() / "Library/Application Support/Godot/app_userdata/Wizard/diag",
)


def _pct(values: list[float], pct: float) -> float:
    if not values:
        return float("nan")
    ordered = sorted(values)
    idx = min(len(ordered) - 1, max(0, round((pct / 100.0) * (len(ordered) - 1))))
    return ordered[idx]


def _read_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def _floats(rows: list[dict[str, str]], key: str) -> list[float]:
    out = []
    for row in rows:
        try:
            out.append(float(row[key]))
        except (KeyError, TypeError, ValueError):
            pass
    return out


def _nearest_event(events: list[dict[str, str]], t_ms: float) -> str:
    best, best_dt = "-", 1e18
    for ev in events:
        dt = t_ms - float(ev["t_ms"])
        if 0 <= dt < best_dt:
            best, best_dt = ev["event"], dt
    return f"{best} (+{best_dt / 1000:.1f}s)" if best != "-" else "-"


def _frame_summary(rows: list[dict[str, str]]) -> dict[str, float]:
    frame_ms = _floats(rows, "frame_ms")
    tickloop_ms = [v / 1000.0 for v in _floats(rows, "tickloop_us")]
    rb = _floats(rows, "rb_depth")
    stretch = _floats(rows, "clock_stretch")
    phys_steps = _floats(rows, "phys_steps")
    return {
        "frames": float(len(rows)),
        "fps.p50": _pct(_floats(rows, "fps"), 50),
        "frame_ms.p50": _pct(frame_ms, 50),
        "frame_ms.p95": _pct(frame_ms, 95),
        "frame_ms.p99": _pct(frame_ms, 99),
        "frame_ms.max": max(frame_ms) if frame_ms else float("nan"),
        "tickloop_ms.p50": _pct(tickloop_ms, 50),
        "tickloop_ms.p99": _pct(tickloop_ms, 99),
        "tickloop_ms.max": max(tickloop_ms) if tickloop_ms else float("nan"),
        "rb_depth.p50": _pct(rb, 50),
        "rb_depth.p99": _pct(rb, 99),
        "rb_depth.max": max(rb) if rb else float("nan"),
        "phys_steps.max": max(phys_steps) if phys_steps else float("nan"),
        "clock_stretch.spread": _pct(stretch, 95) - _pct(stretch, 5),
    }


def _pawn_check(rows: list[dict[str, str]]) -> dict[str, float]:
    if not rows:
        return {}
    by_pawn: dict[str, list[dict[str, str]]] = {}
    for row in rows:
        by_pawn.setdefault(row.get("pawn", "?"), []).append(row)

    out: dict[str, float] = {"pawn_ticks": float(len(rows))}
    for name, pr in sorted(by_pawn.items()):
        owner = pr[0].get("owner", "?")
        tag = f"pawn_{name}[{'own' if owner == '1' else 'rem'}]"
        flips = 0
        grounded_vy: list[float] = []
        airborne_vy: list[float] = []
        steps: list[float] = []  # per-tick position delta magnitude (units/tick) = the "warp"
        airborne = small_vy_airborne = 0
        prev = None
        prev_pos: tuple[float, float, float] | None = None
        prev_tick: int | None = None
        for row in pr:
            try:
                on_floor = int(row["on_floor"])
                vy = float(row["vy"])
                pos = (float(row["px"]), float(row["py"]), float(row["pz"]))
                tick = int(row["net_tick"])
            except (KeyError, ValueError):
                continue
            if prev is not None and prev != on_floor:
                flips += 1
            prev = on_floor
            if on_floor:
                grounded_vy.append(abs(vy))
            else:
                airborne += 1
                airborne_vy.append(abs(vy))
                if abs(vy) < 1.5:
                    small_vy_airborne += 1
            if prev_pos is not None and prev_tick is not None and tick - prev_tick == 1:
                steps.append(math.dist(pos, prev_pos))
            prev_pos, prev_tick = pos, tick
        n = len(pr)
        out[f"{tag}.airborne_pct"] = 100.0 * airborne / n
        out[f"{tag}.stuck_airborne_pct"] = 100.0 * small_vy_airborne / n
        out[f"{tag}.grounded_vy_abs.p95"] = _pct(grounded_vy, 95)
        out[f"{tag}.airborne_vy.p95"] = _pct(airborne_vy, 95)
        out[f"{tag}.on_floor_flips"] = float(flips)
        out[f"{tag}.step.p95"] = _pct(steps, 95)
        out[f"{tag}.step.max"] = max(steps) if steps else 0.0
    return out


def _print_session(session: Path) -> bool:
    frames = _read_csv(session / "frame.csv")
    events = _read_csv(session / "events.csv")
    pawns = _read_csv(session / "pawn.csv")
    meta = {}
    if (session / "meta.json").exists():
        meta = json.loads((session / "meta.json").read_text())

    print(f"\n=== {session.name} ===")
    ctx = meta.get("context", {})
    cfg = meta.get("backend_config", {})
    print(f"  backend={meta.get('backend', '?')} role={ctx.get('role', '?')} "
          f"scenario={ctx.get('scenario', '?')}")
    if cfg:
        print("  config: " + " ".join(f"{k}={v}" for k, v in cfg.items()))
    if not frames:
        print("  (no frame.csv rows)")
        return False

    summary = _frame_summary(frames)
    summary.update(_pawn_check(pawns))
    for key, value in summary.items():
        print(f"  {key:24s} {value:10.3f}")

    print("  rb_depth histogram: " + str(dict(sorted(
        Counter(int(float(r["rb_depth"])) for r in frames if "rb_depth" in r).items()
    ))))

    worst = sorted(frames, key=lambda r: -float(r.get("frame_ms", 0)))[:8]
    print("  worst frames (frame_ms / rb / tick / nearest marker):")
    for row in worst:
        t_ms = float(row["t_ms"])
        print(f"    {float(row['frame_ms']):7.1f}ms  rb={row['rb_depth']:>2}  "
              f"tick={row['net_tick']:>6}  {_nearest_event(events, t_ms)}")

    ok = True
    for pattern, ceiling in THRESHOLDS.items():
        for key in sorted(k for k in summary if pattern in k):
            got = summary[key]
            over = got == got and got > ceiling
            ok = ok and not over
            print(f"  [{'OVER' if over else 'ok  '}] {key} = {got:.3f} (<= {ceiling})")
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
