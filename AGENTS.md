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

## Other conventions

- **Scene tree as source of truth** — prefer authored scene hierarchy over invisible script-only wiring. Sockets and abilities, not greybox sculpture in scripts.
- **Engine and addons first** — use Godot (and existing extensions) fully before adding helpers. Session membership is `multiplayer.get_peers()`; Steam IDs are for Steam connect and display names only.
- **Lint after GDScript changes** — `python tools/run_checks.py --lint-only` (or `make lint`).
- **CI** — `.github/workflows/ci.yml` runs lint and Godot unit tests. Local: `make test`.
