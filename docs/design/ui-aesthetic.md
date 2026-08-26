# UI design aesthetic

**Canonical reference** for UI styling — linked from [AGENTS.md](../../AGENTS.md) for all AI assistants (Cursor, Claude, etc.).

Curated palette and usage rules for **overlays, menus, settings, lobby, pause flow, and HUD chrome**. World geometry, spell VFX, and monster lookdev are out of scope unless explicitly noted.

Machine-readable palette: `[resources/ui/palette.json](../../resources/ui/palette.json)`  
Godot constants and style helpers: `[scripts/ui/ui_palette.gd](../../scripts/ui/ui_palette.gd)`

## Palette


| Name           | Hex       | Role                                                                 |
| -------------- | --------- | -------------------------------------------------------------------- |
| Ink Black      | `#06080f` | Deepest backdrop, scrim base                                         |
| Dark Amethyst  | `#261342` | Accents, gems, flare                                                 |
| Prussian Blue  | `#14213d` | Elevated surfaces, nested panels, tabs, menus                        |
| Hunter Green   | `#355e3b` | Success, active-positive states (e.g. voice live)                    |
| Honey Bronze   | `#e2ab43` | Primary accent — borders, focus, CTAs                                |
| Snow           | `#f6efee` | Primary text on dark surfaces                                        |
| Mist           | `#9699a2` | Cool mid-light between Ink and Snow — toggle on-track, soft lit cues |
| Health Crimson | `#9b2c2c` | HP fill (`fill_swatch` / `HealthBar`)                                |




## Mood

Gothic arcane library at night: deep purples and blues, warm bronze trim, readable snow text. Panels feel like bound tomes or warded glass — framed, not flat.

## Semantic tokens

Use `UiPalette` constants instead of hard-coded RGB in new UI work:


| Token            | Constant              | Typical use                                         |
| ---------------- | --------------------- | --------------------------------------------------- |
| Deep background  | `BACKGROUND_DEEP`     | Full-screen menu backdrop                           |
| Primary surface  | `BACKGROUND_PRIMARY`  | Nested wells, amethyst accents — not button fill    |
| Elevated surface | `BACKGROUND_ELEVATED` | Modal panels, nested containers                     |
| Button fill      | `BUTTON_FILL`         | Menu / settings buttons — lifted Prussian `#1e3054` |
| Button hover     | `BUTTON_HOVER`        | Hover / pressed-adjacent — `#2a4068`                |
| Primary accent   | `ACCENT_PRIMARY`      | 2px borders, selected tab, key actions              |
| Success / live   | `ACCENT_SUCCESS`      | Connected, speaking, confirmed                      |
| Primary text     | `TEXT_PRIMARY`        | Titles, labels, body                                |
| Muted text       | `TEXT_MUTED`          | Secondary labels, hints                             |
| Scrim            | `SCRIM`               | Overlay dimmer over gameplay                        |
| Health fill      | `HEALTH_FILL`         | Status-bar fill when `fill_swatch` is Health        |
| Mist             | `MIST`                | Toggle on-track / soft highlight (`Swatch.MIST`)    |




## Component patterns



### Overlay stack

1. `ColorRect` scrim — `UiPalette.SCRIM`, full viewport, `mouse_filter` as needed.
2. Centered `PanelContainer` — `UiPalette.panel_style()` or equivalent StyleBox with `BACKGROUND_ELEVATED` + `BORDER_DEFAULT`.
3. Inner `MarginContainer` — 16–20px margins.



### Buttons

- **Paint (shared):** Theme `Button` and `ColorPickerButton` — `BUTTON_FILL`, `BORDER_DEFAULT` 2px, 8px radius. Hover uses `BUTTON_HOVER`. Do not fill buttons with Amethyst on Prussian panels.
- **Menu CTA size (once):** `[scenes/ui/scaffolding/menu_button.tscn](../../scenes/ui/scaffolding/menu_button.tscn)` — 280×64, left-aligned stock `Button`. Paint comes from the Theme; override `text` / `icon` only.
- **Roles:** `theme_type_variation` `PrimaryButton` / `DangerButton` on any `Button`. Settings footer stays a compact themed `Button`.
- **Labels:** set Theme Type Variation `TitleLabel` / `MutedLabel` / `CaptionLabel` on a stock `Label`. The 2D editor shows it immediately.



### Status / resource bars

- **Generic:** `[scenes/ui/scaffolding/status_bar.tscn](../../scenes/ui/scaffolding/status_bar.tscn)` — title, value label, increment ticks, optional tick numbers. Inspector: `tick_divisions`, `show_title`, `show_value_label`, `show_tick_labels`, `bar_theme_variation`, `track_swatch`, `fill_swatch` (palette fill, including Health Crimson), and flare placements + `flare_swatch`. Bronze outline is Theme-constant, not per-instance.
- **Script API:** `set_value` / `set_maximum` / `set_amount(current, maximum)` snap the fill. `tween_value` / `tween_amount` animate it. `get_value` / `get_maximum` read the current range.
- **Binding:** Bars do not poll. Call the setters, or pass the local `Health` into `GameHud.configure(...)` so the HUD HP bar follows `Health.changed` (damage and heal).
- **Health:** `[health_bar.tscn](../../scenes/ui/scaffolding/health_bar.tscn)` — `HP` label, HealthBar fill, increment lines, no numeric tick row (v11).
- Ticks redraw on resize / export change only — not every frame.
- **Flares:** `[title_flare.tscn](../../scenes/ui/scaffolding/title_flare.tscn)` — `show_rule`, `diamond_align` (Left / Center / Right), `diamond_swatch`.



### Typography

- Headings and body on dark panels: `TEXT_PRIMARY`.
- Supporting copy: `TEXT_MUTED`.
- Disabled controls: `TEXT_DISABLED`.
- Do not use pure white or legacy gold RGB tuples in new UI — map to palette tokens.
- Headings: Theme Type Variation `TitleLabel`. Supporting copy: `MutedLabel`. Captions: `CaptionLabel`.


### Tabs and toggles

- Selected tab font: `TEXT_PRIMARY` or a lightened `ACCENT_PRIMARY`.
- Unselected: `TEXT_MUTED`.
- Hover: between muted and primary.
- Active toggle / connected state may use `ACCENT_SUCCESS` for the indicator.
- Settings uses a stock `TabContainer`. Child node names are the tab titles; `current_tab` in the Inspector picks the visible page in the 2D editor. Paint is the Theme (`TabBar` / `TabContainer`).
- On/off rows instance `[toggle_switch.tscn](../../scenes/ui/scaffolding/toggle_switch.tscn)` — pill only (no panel). Inspector: `on_swatch` (default Mist), `off_swatch` (default Ink), `thumb_swatch` (default Snow). Outline is bronze from the palette. Multi-way choices instance `[toggle_slider.tscn](../../scenes/ui/scaffolding/toggle_slider.tscn)`. Inspector: `options` (named entries), `selected`. Runtime: `get_options` / `set_options`, `get_option_text` / `find_option`, `get_selected` / `set_selected`, `get_selected_text` / `set_selected_text`; listen on `selected_changed`. Host lobby uses Local / LAN / Steam.
- Color rows use a stock `ColorPickerButton` (themed like `Button`).
- Volume / opacity / numeric **Settings** rows instance `[value_slider.tscn](../../scenes/ui/scaffolding/value_slider.tscn)` — HSlider + clickable `LineEdit`, with division marks drawn into the track. Inspector: `min_value` / `max_value`, `default_value` (+ tool buttons Set Current as Default / Reset to Default), `tick_divisions` (interior dividers: 1 = halves, 2 = thirds, …), `show_tick_labels`, `snap_to_divisions`, `value_kind` (Float / Int), `show_as_percent` (1.0 = 100% unity — mic dial is 0–2 so midpoint is 100%; past midpoint eases up to ~5× hearback/VoIP gain), `step_size`, `tick_swatch` / `tick_label_swatch`. Runtime: `value_changed`, `set_value_no_signal`, `reset_to_default`, `set_current_as_default`. Lobby / roster mix uses a stock themed `HSlider`, not this prefab.
- Bronze vs danger vs health is a Theme type variation (`DangerButton`, `HealthBar`, `fill_swatch` on status bars), not a per-instance outline export. Tweaks show in the 2D editor without Play.



## Do / don't

**Do**

- Reference `UiPalette` or `palette.json` when adding or restyling UI.
- Keep bronze borders at 2px on framed panels and primary buttons.
- Use consistent corner radii (8 buttons, 10 panels).

**Don't**

- Introduce new accent hues for menus without updating this doc and `palette.json`.
- Pull gameplay or environment colors into overlay chrome.
- Scatter one-off `Color(...)` literals in UI scripts when a semantic token exists.
- Nest Settings chrome (`value_slider`, device pickers, mic test) onto lobby / roster rows.



## Editable screens (open these in the 2D editor)

Packed scenes stay visible so you can layout chrome without playing. Runtime `_ready()` hides overlays. Instances under `game_app.tscn` / `arena.tscn` stay `visible = false` so they do not cover other states.


| Screen       | Scene to open                                                                        |
| ------------ | ------------------------------------------------------------------------------------ |
| Main menu    | `scenes/menu.tscn`                                                                   |
| Pause        | `scenes/ui/pause_menu.tscn` (settings child stays hidden — edit settings below)      |
| Settings     | `scenes/ui/settings_panel.tscn`                                                      |
| Player menu  | `scenes/ui/player_menu.tscn` — Inspector `editor_tab` for Inventory / Spells / Guide |
| Join         | `scenes/ui/join.tscn` — enter a code and connect                                     |
| Lobby        | `scenes/ui/lobby.tscn` — Inspector `editor_layout` for Host / Guest                  |


Slot prefabs: `inventory_slot.tscn`, `spell_menu_slot.tscn`, `lobby_player_row.tscn`.

## Migrating existing UI

Main menu, pause, settings, lobby, player menu, and HUD chrome inherit the project Theme. When touching leftover screens (books), drop inline RGB StyleBoxes and use `UiPalette` / Theme type variations.

## Theme + prefab workflow

No editor plugin. Compose in the FileSystem and scene tree.

```
UiPalette → Theme     fill, border, fonts (shared)
scaffolding/*.tscn    structure (diamonds, ticks, size)
menu / HUD scenes     instances + text/icon/export overrides
```

1. Edit colors in `[scripts/ui/ui_palette.gd](../../scripts/ui/ui_palette.gd)` and `[resources/ui/palette.json](../../resources/ui/palette.json)`.
2. Rebuild the Theme: `godot --headless --path . --script res://tools/generate_ui_theme.gd`
3. Edit a prefab under `[scenes/ui/scaffolding/](../../scenes/ui/scaffolding/)` for shape. Prefabs reference the Theme (so the 2D editor shows paint without copied StyleBoxes).
4. Drag that `.tscn` into a menu or HUD. Override `text` / `icon` / exports only. Keep instances linked.


| Prefab                 | Path                                                                           |
| ---------------------- | ------------------------------------------------------------------------------ |
| Menu button            | `menu_button.tscn` — 280×64 left-aligned `Button`; paint is the Theme          |
| Title flare            | `title_flare.tscn` — rule on/off, diamond align + swatch                       |
| Status / health bar    | `status_bar.tscn`, `health_bar.tscn` — `fill_swatch` for HP crimson            |
| HUD slot / row         | `hud_slot.tscn`, `hud_slot_row.tscn` — `HudSlot` type variation                |
| Inventory / spell slot | `inventory_slot.tscn`, `spell_menu_slot.tscn`                                  |
| Lobby player row       | `lobby_player_row.tscn` — mute glyph + themed `HSlider` (Settings keeps ticks)  |
| Toggle switch          | `toggle_switch.tscn` — on/off pill                                             |
| Toggle slider          | `toggle_slider.tscn` — sliding window over Inspector-named `options`           |
| Value slider           | `value_slider.tscn` — track ticks + labels, max, int/float, %, editable, default |


Mockups: menus `docs/design/mockups/menus/v6-*.png`, HUD `docs/design/mockups/hud/v11-hud.png`.

## Extending the system

When adding tokens (spacing scale, font sizes, animation timing):

1. Add to this doc with a short usage note.
2. Mirror in `palette.json` under a new top-level key if machine-readable.
3. Expose Godot constants or helpers in `ui_palette.gd`.
4. Rebuild the Theme so scenes inherit the new look.



## Authoring a new prefab

Prefabs follow a freeze: custom silhouette, used on more than one screen, and preview needs
the structure. `@tool` only for that silhouette (ticks, pills, flares), `@export` parameters
with unchanged-value early returns, `UiPalette.Swatch` for **fill** roles (not per-instance
outlines), no repaint from `NOTIFICATION_THEME_CHANGED`, and coverage in
`tests/unit/test_ui_scaffolding_chrome.gd`. Stock `Button` / `Label` / `TabContainer` /
`ColorPickerButton` / `HSlider` use Theme type variations — do not wrap them, and do not nest
Settings `value_slider` onto lobby rows. The full workflow lives in the
`building-ui-scaffolding` skill
(`[.cursor/skills/building-ui-scaffolding/SKILL.md](../../.cursor/skills/building-ui-scaffolding/SKILL.md)`).