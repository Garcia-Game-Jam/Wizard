# Netcode diagnostics (NetDiag)

Structured capture for the "netfox feels choppy" investigation. The goal is to
turn "choppy" into numbers we can compare across one-change-at-a-time experiments.

## Turn it on

- **In game:** Settings → Developer → **Netcode diagnostics capture**. A red
  `◉ NET DIAG` overlay shows while it records.
- **Headless / automation:** set `WIZARD_NET_DIAG=1` before Godot starts.

Each match writes one folder: `user://diag/<timestamp>/`
(`…/AppData/Roaming/Godot/app_userdata/Wizard/diag/` on Windows).

## What slice 1 captures

`meta.json` — self-describing header: build, OS/CPU/GPU, role (host/guest/solo),
and the netfox settings that matter (`sync_to_physics`, `tickrate`,
`physics_ticks_per_second`, `max_ticks_per_frame`, diff/broadcast flags). Every
capture carries the config it ran under, so runs stay comparable.

`frame.csv` — one row per rendered frame:

| column | meaning |
|---|---|
| `tickloop_us` | wall time inside netfox's tick loop this frame |
| `rb_depth` | ticks resimulated in the rollback pass (`NetworkPerformance`) |
| `proc_ms` / `phys_ms` | `_process` / `_physics_process` frame cost |
| `fps` | engine FPS monitor |
| `clock_stretch` / `clock_offset` | netfox clock health (rubber-banding shows here) |
| `node_count` / `coll_pairs` / `active_objs` | scene + physics load |
| `net_tick` / `peers` | context |

This needs **no gameplay-code changes** — NetDiag only hooks `NetworkTime`
signals and the `Performance` monitors.

## Analyse

```bash
python tools/analyze_netdiag.py --all
python tools/analyze_netdiag.py <session_dir> [<session_dir> ...]
```

Prints percentiles per session and PASS/FAIL against the (loose, first-pass)
ceilings in `THRESHOLDS`. Tighten those as real baselines land.

## Roadmap

- **Slice 1 (this):** frame stream + overlay + toggle + analyzer skeleton.
- **Slice 2:** `begin/end_session` context enrichment (scenario id, `NetworkSimulator` params).
- **Slice 3:** per-pawn per-fresh-tick rows — predicted vs authoritative position,
  `correction_mag`, `vy`, `is_on_floor` — the `host-feel.log` successor.
- **Slice 4:** `direct_space_state` query counter routed through the projectile /
  monster hit paths.
- **Later:** wire thresholds into the LAN E2E as a regression guard.

## Experiment loop

1. Capture a baseline (≥5 runs per network condition), commit the numbers.
2. Pre-register the pass criterion for the next change.
3. Change **one** variable (prefer a flag/setting so it A/Bs in one build).
4. Re-run the identical scenario, compare distributions, keep only if p95 beats
   run-to-run spread.
5. Log it: hypothesis, change, numbers, verdict, decision.

First hypothesis queued: `netfox/time/sync_to_physics = true` +
`physics_ticks_per_second = 30`.
