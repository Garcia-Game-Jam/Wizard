# Instructions for AI assistants

## UI design (menus, overlays, HUD)

**Arena loop (locked):** [docs/design/arena.md](docs/design/arena.md) — wizards in a pit; rule of 3 (three fights, then a shared spell).

**Live pit roster (locked while evaluating):** spells `fireball` + `ward`; monsters charger + ember. Everything else stays under `scenes/spells/evaluating/` and `scenes/monsters/evaluating/`.

**Greybox freeze (Option A):** iterate mechanics, not sculpture. Character/monster scenes keep sockets (`%Body`, `%Head`, `%Eyes`), `Health`, `Abilities`, and **one** root `CollisionShape3D`. Do not add decorative meshes, extra part colliders, or `MeshInstance3D.new()` / `OmniLight3D.new()` in combat/ability scripts. Spawned tells are PackedScenes under `scenes/fx/` (or an existing spell scene). Net: rewindable fields on the body, or a replicated spawn — `NetLiveness.after_spawn` is tick motion, not “it exists on guests.”

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
Guards, all three of which must stay green:

- `NetClock.move_character` warns in debug builds when a body out-runs its radius
  (every character moves through it, so this catches the whole class).
- `analyze_netdiag.py` fails a capture whose `step.max` exceeds the radius.
- `tests/unit/test_knockback_bleed.gd` asserts knockback is tickrate-independent.

**Per-tick impulses must be delta-scaled.** A flat `velocity += x * 0.35` per
tick silently compounds with tickrate — that bug turned a 9 m/s hit into 40 m/s
at 60 Hz. Use a per-second constant times `delta`.

Known outstanding: `dash_speed = 20.0` exceeds the 60 Hz budget. Clamp or substep.

## Other conventions

- **Scene tree as source of truth** — prefer authored scene hierarchy over invisible script-only wiring. Sockets and abilities, not greybox sculpture in scripts.
- **Engine and addons first** — use Godot (and existing extensions) fully before adding helpers. Session membership is `multiplayer.get_peers()`; Steam IDs are for Steam connect and display names only.
- **Lint after GDScript changes** — `python tools/run_checks.py --lint-only` (or `make lint`).
- **CI** — `.github/workflows/ci.yml` runs lint and Godot unit tests. Local: `make test`.
