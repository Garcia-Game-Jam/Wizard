# Instructions for AI assistants

## UI design (menus, overlays, HUD)

**Arena loop (locked):** [docs/design/arena.md](docs/design/arena.md) — wizards in a pit; rule of 3 (three fights, then a shared spell).

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

- **Scene tree as source of truth** — prefer authored scene hierarchy over invisible script-only wiring.
- **Engine and addons first** — use Godot (and existing extensions) fully before adding helpers. Session membership is `multiplayer.get_peers()`; Steam IDs are for Steam connect and display names only.
- **Lint after GDScript changes** — `python tools/run_checks.py --lint-only` (or `make lint`).
- **CI** — `.github/workflows/ci.yml` runs lint and Godot unit tests. Local: `make test`.
