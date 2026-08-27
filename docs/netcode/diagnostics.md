# Netcode diagnostics (NetDiag)

Capture for comparing one-change-at-a-time netcode experiments. Do not add
columns until a question needs one.

## Turn it on

- **In game:** Settings → Developer → **Netcode diagnostics capture**. A red
  `◉ NET DIAG` overlay shows while it records.
- **Headless / automation:** set `WIZARD_NET_DIAG=1` before Godot starts.

Each match writes one folder: `user://diag/<timestamp>_<role>_<pid>/`
(`…/AppData/Roaming/Godot/app_userdata/Wizard/diag/` on Windows).

## What a capture contains

`meta.json` — build, OS/CPU/GPU, role (host/guest/solo), `backend`, and
`backend_config` (`sync_to_physics`, `tickrate`, `physics_ticks_per_second`,
`max_ticks_per_frame`, diff/broadcast flags).

`frame.csv` — one row per rendered frame: `tickloop_us`, `rb_depth`,
`proc_ms` / `phys_ms`, `fps`, `clock_stretch` / `clock_offset` / `rtt`,
scene + physics load, `net_tick` / `peers`.

`pawn.csv` / `render.csv` / `events.csv` — rewind-body samples, on-screen pose,
named markers.

NetDiag reads netcode-specific values through `NetProbe`
(`scripts/net/net_probe.gd`). Gameplay still goes through the `Net*` helpers,
never `get_node("/root/NetworkTime")` directly.

## Analyse

```bash
python tools/analyze_netdiag.py --all
python tools/analyze_netdiag.py <session_dir> [<session_dir> ...]
```

PASS/FAIL is against `THRESHOLDS` in `tools/analyze_netdiag.py`. Read the
summary, not just RESULT:

- `frame_ms.max` is reported, not gated. Live dump scenes (charger, ember)
  are `load()`ed when the arena starts, so `dump_spawn` `load=` should be noise.
  A remaining spike at `encounter_begin` is instantiate / first draw, not
  disk. Use `frame_ms.p99` for ongoing lag.
- Dump split (no new columns): `dump_cleared` / `dump_spawn` (`load=`
  `inst=` `enroll=` microseconds) / `dump_done` / deferred `dump_rewind`
  (rollback ticks). `rb_depth=1` on a long frame means it is not the rewind
  spike (`rb_depth.max` in the 30s is usually a different frame).
- `step.max` is reported; the gate is owned-pawn `step.p95` vs capsule radius
  (0.237 m). Dash can spike a single tick over the radius.
- `stuck_airborne_pct` on `[rem]` is ignored. Guests do not `move_and_slide`
  host-owned pawns the same way, so `is_on_floor()` stays stale.
- `rtt` / `clock_offset` are printed from `frame.csv`.

## Experiment loop

1. Capture a baseline, read percentiles (not a single FAIL).
2. Change **one** variable.
3. Re-run the identical scenario, compare distributions.

Current contract: `netfox/time/sync_to_physics = true`, physics 60 Hz, net
tick 30 Hz.
