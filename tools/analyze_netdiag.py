#!/usr/bin/env python3
"""Summarise NetDiag capture folders (user://diag/<stamp>_<role>_<pid>/).

Usage:
    python tools/analyze_netdiag.py <session_dir> [<session_dir> ...]
    python tools/analyze_netdiag.py --all           # scans the default diag root

Reads frame.csv (real per-frame time, rollback depth, tick-loop cost, clock
health), events.csv (named markers) and pawn.csv (per-tick floor state). Prints
percentiles, the worst frames with their nearest marker, and a floor-state check.
PASS/FAIL is against THRESHOLDS. frame_ms.max and step.max are reported but not
gates (dump hitch / dash spike). Remote is_on_floor is ignored — guests do not
slide host-owned pawns, so stuck_airborne_pct on [rem] is a probe lie.
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
# summary so pawn-specific keys (pawn_1[own].stuck_airborne_pct) are covered.
# frame_ms.max and step.max stay in the printout but are not gates.
THRESHOLDS = {
    "frame_ms.p99": 20.0,
    "rb_depth.p99": 3.0,
    "tickloop_ms.p99": 6.0,
    "clock_stretch.spread": 0.35,
    "tick_factor.regress_pct": 2.0,
    "stuck_airborne_pct": 5.0,
    "grounded_vy_abs.p95": 1.0,
    "on_floor_flips": 10.0,
    "render_freeze_pct": 1.0,
    "render_reversal_pct": 2.0,
    "step.p95": 0.237,
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
    # tick_factor rises 0->1 then resets (big negative step). A *small* negative
    # step (-0.25 < d < -0.01) is a mid-rise regression = interpolation going
    # backwards. A reset (d <= -0.25) is normal and not counted.
    tf_delta = _floats(rows, "tick_factor_delta")
    tf = _floats(rows, "tick_factor")
    tf_regress = sum(1 for d in tf_delta if -0.25 < d < -0.01)
    tf_pinned = sum(1 for i, v in enumerate(tf)
                    if v > 0.98 and i < len(tf_delta) and abs(tf_delta[i]) < 0.001)
    n = max(len(rows), 1)
    extra = {
        "tick_factor.regress_pct": 100.0 * tf_regress / n,
        "tick_factor.pinned_pct": 100.0 * tf_pinned / n,
    }
    return extra | {
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
        "rtt.p50": _pct(_floats(rows, "rtt"), 50),
        "rtt.p95": _pct(_floats(rows, "rtt"), 95),
        "clock_offset.p50": _pct(_floats(rows, "clock_offset"), 50),
        "clock_offset.p95": _pct(_floats(rows, "clock_offset"), 95),
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


def _render_check(rows: list[dict[str, str]]) -> dict[str, float]:
    """Smoothness of the on-screen (interpolated) pose. This is the metric that
    matches what the player's eye sees during a knock-up."""
    if not rows:
        return {}
    by_pawn: dict[str, list[dict[str, str]]] = {}
    for row in rows:
        by_pawn.setdefault(row.get("pawn", "?"), []).append(row)

    out: dict[str, float] = {"render_frames": float(len(rows))}
    for name, pr in sorted(by_pawn.items()):
        pr.sort(key=lambda r: int(r["frame"]))
        deltas: list[tuple[float, float, float, float]] = []  # dx,dy,dz,dt_s
        for a, b in zip(pr, pr[1:]):
            try:
                dt = (float(b["t_ms"]) - float(a["t_ms"])) / 1000.0
                d = (float(b["px"]) - float(a["px"]),
                     float(b["py"]) - float(a["py"]),
                     float(b["pz"]) - float(a["pz"]))
            except (KeyError, ValueError):
                continue
            if dt > 0:
                deltas.append((*d, dt))
        if len(deltas) < 3:
            continue
        mags = [math.dist((0, 0, 0), d[:3]) for d in deltas]
        n_moving = max(sum(1 for m in mags if m > 0.003), 1)  # ~0.4 u/s at 144fps
        # freeze: a near-still frame flanked by motion
        freezes = sum(1 for i in range(1, len(mags) - 1)
                      if mags[i] < 0.0005 and mags[i - 1] > 0.005 and mags[i + 1] > 0.005)
        # reversal: consecutive move vectors point opposite (dot < 0), both real
        reversals = 0
        jerks: list[float] = []
        for i in range(1, len(deltas)):
            p, q = deltas[i - 1], deltas[i]
            vp = tuple(c / p[3] for c in p[:3])
            vq = tuple(c / q[3] for c in q[:3])
            jerks.append(math.dist(vp, vq))
            if mags[i - 1] > 0.005 and mags[i] > 0.005:
                if sum(a * b for a, b in zip(p[:3], q[:3])) < 0:
                    reversals += 1
        tag = f"render_{name}"
        out[f"{tag}.jerk.p95"] = _pct(jerks, 95)
        out[f"{tag}.jerk.max"] = max(jerks) if jerks else 0.0
        out[f"{tag}.render_freeze_pct"] = 100.0 * freezes / len(mags)
        out[f"{tag}.render_reversal_pct"] = 100.0 * reversals / n_moving
    return out


def _print_session(session: Path) -> bool:
    frames = _read_csv(session / "frame.csv")
    events = _read_csv(session / "events.csv")
    pawns = _read_csv(session / "pawn.csv")
    render = _read_csv(session / "render.csv")
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
    summary.update(_render_check(render))
    for key, value in summary.items():
        print(f"  {key:30s} {value:10.3f}")

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
        for key in sorted(k for k in summary if _is_gate_key(k, pattern)):
            got = summary[key]
            over = got == got and got > ceiling
            ok = ok and not over
            print(f"  [{'OVER' if over else 'ok  '}] {key} = {got:.3f} (<= {ceiling})")
    print(f"  RESULT: {'PASS' if ok else 'FAIL'}")
    return ok


def _is_gate_key(key: str, pattern: str) -> bool:
    if pattern not in key:
        return False
    # Guests do not move_and_slide host-owned pawns; is_on_floor stays stale.
    if "[rem]" in key and pattern in (
        "stuck_airborne_pct",
        "grounded_vy_abs.p95",
        "on_floor_flips",
    ):
        return False
    return True


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
