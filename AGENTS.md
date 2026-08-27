# Instructions for AI assistants

## UI design (menus, overlays, HUD)

**Arena loop (locked):** [docs/design/arena.md](docs/design/arena.md) — wizards in a pit; rule of 3 (three fights, then a shared spell).

**Combat contract:** [docs/design/combat.md](docs/design/combat.md) — connect (who), then a payload list of effect Resources (what).

**Live pit roster (locked while evaluating):** spells `fireball` + `ward`; monsters charger + ember. Everything else stays under `scenes/spells/evaluating/` and `scenes/monsters/evaluating/`.

**Greybox freeze (Option A):** iterate mechanics, not sculpture. Character/monster scenes keep sockets (`%Body`, `%Head`, `%Eyes`), `Abilities`, and **one** root `CollisionShape3D`. HP, slow, burn, and knock are **exported properties** on `Character` / `Player` — not child nodes. Player `Stun` is the exception (ram lock + stars). Do not add decorative meshes, extra part colliders, or `MeshInstance3D.new()` / `OmniLight3D.new()` in combat/ability scripts. Spawned tells are PackedScenes under `scenes/fx/` (or an existing spell scene). Net: rewindable fields on the body, or a replicated spawn — `NetLiveness.after_spawn` is tick motion, not “it exists on guests.”

**Read before changing UI chrome:** [docs/design/ui-aesthetic.md](docs/design/ui-aesthetic.md)

| Asset | Path |
|-------|------|
| Design guide (canonical) | `docs/design/ui-aesthetic.md` |
| Palette data (JSON) | `resources/ui/palette.json` |
| Godot tokens & helpers | `scripts/ui/ui_palette.gd` (`UiPalette`) |
| Designed widgets | `scenes/ui/scaffolding/` — drag into menus/HUD; override text/icon/exports |

**Scope:** overlays, menus, settings, lobby, pause flow, and HUD chrome.
**Out of scope:** world geometry, spell VFX, monster lookdev (unless explicitly restyling HUD).

When extending the palette or tokens, update the guide, JSON, and `ui_palette.gd` together.

## Collision + movement speed (netcode-critical)

**No CSG collision in the live pit.** `use_collision` on a CSG node bakes a
*concave trimesh*, which has no interior — once a body's shape crosses a face
there is no depenetration direction and `move_and_slide` resolves to zero
displacement until velocity happens to point back out. Arena geometry is
`StaticBody3D` + **convex** shapes (`BoxShape3D` for the rectangular pit). CSG is
an authoring tool; bake it before it ships.

**A body may not travel further than its own collision radius in one tick.**
Player capsule radius is 0.237 m, so at 60 Hz the ceiling is ~14 m/s. Exceeding
it lets the body penetrate geometry; rollback then resimulates *from inside the
wall* every tick, and the pawn appears to freeze mid-air on the other peer.
Guards:

- `NetClock.move_character` warns in debug builds when a body out-runs its radius
  (every character moves through it, so this catches the whole class). Substeps
  when a single slide would exceed the radius.
- `analyze_netdiag.py` flags owned-pawn `step.p95` over the radius; `step.max`
  is reported (dash spikes) but is not a merge gate.

**Per-tick impulses must be delta-scaled.** A flat `velocity += x * 0.35` per
tick silently compounds with tickrate — that bug turned a 9 m/s hit into 40 m/s
at 60 Hz. Use a per-second constant times `delta`.

**Characters are always `MOTION_MODE_GROUNDED` — never `MOTION_MODE_FLOATING`.**
Players and NPCs alike, walking or airborne or knocked back or stunned. In
FLOATING mode `move_and_slide` discards the *entire* motion vector — vertical
included — when the body is pressed into a wall at speed, and leaves the
into-wall velocity untouched. A wizard fireballed into the pit wall hung mid-air
for 67 of 70 ticks (same in Jolt and Godot Physics); GROUNDED resolves the
identical case correctly. **Airborne is expressed as `floor_snap_length = 0`,
not a mode change.** `tests/unit/test_wall_slide_stall.gd` knocks a capsule into
a box wall and requires it still falls.

## Other conventions

- **Scene tree as source of truth** — sockets and abilities are authored nodes. HP and status are exported fields on `Character`/`Player` (Stun node is the ram exception). Not greybox sculpture in scripts.
- **Engine and addons first** — use Godot (and existing extensions) fully before adding helpers. Session membership is `multiplayer.get_peers()`; Steam IDs are for Steam connect and display names only.
- **Lint after GDScript changes** — `python tools/run_checks.py --lint-only` (or `make lint`).
- **CI** — `.github/workflows/ci.yml` runs lint and Godot unit tests. Local: `make test`.
