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
`backend` (`netfox`), and `backend_config` — the settings that matter for
comparison (`sync_to_physics`, `tickrate`, `physics_ticks_per_second`,
`max_ticks_per_frame`, diff/broadcast flags). Every capture carries the config it
ran under, so runs stay comparable.

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

This needs **no gameplay-code changes** — NetDiag reads everything netcode-
specific through `NetProbe` and otherwise only samples `Performance` monitors.

## Backend-neutral by design

NetDiag never touches netfox directly. It talks to `NetProbe`
(`scripts/net/net_probe.gd`), a thin read model:

| method | meaning | netfox-less fallback |
|---|---|---|
| `backend_id()` | label for meta.json + overlay | `"none"` |
| `is_running()` | clock/session live | `false` |
| `current_tick()` | net tick | `0` |
| `rollback_depth()` | ticks resimulated last frame | `0` |
| `clock_health()` | `{stretch, offset, rtt}` | `{1.0, 0.0, 0.0}` |
| `pop_tick_loop()` | `{us, ticks}` since last frame | `{}` |
| `config_snapshot()` | settings for meta.json | `{}` |
| `peer_count()` | via Godot `multiplayer` | generic |

`NetProbeNetfox` (`scripts/net/net_probe_netfox.gd`) is the **only file in the
diagnostics path that knows netfox** — signal names, autoloads, `netfox/*`
settings keys. Swapping backends is: write `NetProbePhoton`, add one branch to
`NetProbe.create()`. The CSV schema is fixed, so baselines and
`analyze_netdiag.py` keep working across a backend change — which is exactly what
you want when A/B-ing netfox against an alternative.

A backend without a concept (Photon has no rollback loop) returns the neutral
value and those columns read 0 — graceful, not broken.

### Wider coupling (not part of this seam)

The diagnostics are decoupled; the **game's** net layer is not, and a real
backend swap is a large project regardless. The netfox binding points to budget
for:

- `scripts/net/net_rewindable_mover.gd` — the factory that builds
  `RollbackSynchronizer` / `TickInterpolator` / `PredictiveSynchronizer`.
- `_rollback_tick(delta, tick, is_fresh)` implemented on ~15 nodes (players,
  monsters, projectiles, cover, telegraph) — netfox's callback shape. Each
  already delegates to a plain `_simulate_*()`; a swap re-points the shim.
- `NetClock` (`physics_factor`, `is_initial_sync_done`), `NetLiveness`
  (`PredictiveSynchronizer`), `PlayerNetInput` (`before_tick_loop` hook).
- `netfox/*` ProjectSettings, `test_netfox_contract.gd`.

`NetClock`, `NetAuthority`, `NetWorldEvent`, `NetRewindableProfiles` are already
backend-neutral or close to it. **Discipline for new code:** gameplay scripts go
through the `Net*` helpers, never `get_node("/root/NetworkTime")` or `netfox/*`
settings directly.

## Analyse

```bash
python tools/analyze_netdiag.py --all
python tools/analyze_netdiag.py <session_dir> [<session_dir> ...]
```

Prints percentiles per session and PASS/FAIL against the (loose, first-pass)
ceilings in `THRESHOLDS`. Tighten those as real baselines land.

## Roadmap

- **Slice 1 (this):** frame stream + overlay + toggle + analyzer skeleton, all
  behind the `NetProbe` seam.
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
