## UI color tokens for overlays, menus, and HUD chrome.
## Source of truth: resources/ui/palette.json · Design guide: docs/design/ui-aesthetic.md
class_name UiPalette
extends RefCounted

## Exported Swatch values serialize as ints, so inserting a name mid-list silently
## recolors every scene that already picked one. Only append.
enum Swatch {
	INK,
	AMETHYST,
	PRUSSIAN,
	HUNTER,
	BRONZE,
	SNOW_WHITE,
	HEALTH,
	## Cool mid-light between Ink and Snow — toggle on-track, soft highlights.
	MIST,
}

# Base palette
const INK_BLACK := Color("06080f")
const DARK_AMETHYST := Color("261342")
const PRUSSIAN_BLUE := Color("14213d")
const HUNTER_GREEN := Color("355e3b")
const HONEY_BRONZE := Color("e2ab43")
const SNOW := Color("f6efee")
const MIST := Color("9699a2")

# Semantic roles
const BACKGROUND_DEEP := INK_BLACK
const BACKGROUND_PRIMARY := DARK_AMETHYST
const BACKGROUND_ELEVATED := PRUSSIAN_BLUE
## Same hue as Prussian, one step lighter — buttons on Ink or Prussian panels.
const BUTTON_FILL := Color("1e3054")
const BUTTON_HOVER := Color("2a4068")
const ACCENT_PRIMARY := HONEY_BRONZE
const ACCENT_SUCCESS := HUNTER_GREEN
const TEXT_PRIMARY := SNOW
const TEXT_MUTED := Color(SNOW, 0.72)
const TEXT_DISABLED := Color(SNOW, 0.45)
const BORDER_DEFAULT := HONEY_BRONZE
const BORDER_HOVER := Color("f0c05a")
const SCRIM := Color(INK_BLACK, 0.62)
const HEALTH_FILL := Color("9b2c2c")
const HUD_SLOT_BG := Color(PRUSSIAN_BLUE, 0.94)
const HUD_SLOT_EMPTY := Color(INK_BLACK, 0.94)

# Shared layout tokens for panels and buttons
const PANEL_CORNER_RADIUS := 10
const BUTTON_CORNER_RADIUS := 8
const PANEL_BORDER_WIDTH := 2

const _BUTTON_STYLE_STATES := ["normal", "hover", "pressed", "disabled", "focus"]


static func swatch_color(swatch: Swatch) -> Color:
	match swatch:
		Swatch.AMETHYST:
			return DARK_AMETHYST
		Swatch.PRUSSIAN:
			return PRUSSIAN_BLUE
		Swatch.HUNTER:
			return HUNTER_GREEN
		Swatch.BRONZE:
			return HONEY_BRONZE
		Swatch.SNOW_WHITE:
			return SNOW
		Swatch.HEALTH:
			return HEALTH_FILL
		Swatch.MIST:
			return MIST
		_:
			return INK_BLACK


static func apply_outline(
	box: StyleBoxFlat,
	show_outline: bool,
	swatch: Swatch,
	width: int = PANEL_BORDER_WIDTH
) -> void:
	if box == null:
		return
	if show_outline:
		box.set_border_width_all(width)
		box.border_color = swatch_color(swatch)
	else:
		box.set_border_width_all(0)
		box.border_color = Color(0, 0, 0, 0)


## get_theme_stylebox() returns the local override once one exists, so reading it again
## would layer an override on an override and permanently detach the control from the
## Theme. Drop ours first so the Theme's own box is always the starting point.
static func _theme_stylebox(control: Control, style_name: String) -> StyleBox:
	if control.has_theme_stylebox_override(style_name):
		control.remove_theme_stylebox_override(style_name)
	return control.get_theme_stylebox(style_name)


## NOTE: the add/remove override calls below re-emit NOTIFICATION_THEME_CHANGED. Never
## call these from a _notification handler that listens for it — that recurses until the
## stack blows. Repaint from _ready and from export setters instead.
static func paint_button_outline(
	button: BaseButton,
	show_outline: bool,
	swatch: Swatch,
	width: int = PANEL_BORDER_WIDTH
) -> void:
	if button == null:
		return
	for style_name in _BUTTON_STYLE_STATES:
		var src := _theme_stylebox(button, style_name)
		if not src is StyleBoxFlat:
			continue
		var box := (src as StyleBoxFlat).duplicate() as StyleBoxFlat
		apply_outline(box, show_outline, swatch, width)
		button.add_theme_stylebox_override(style_name, box)


static func paint_panel_outline(
	control: Control,
	show_outline: bool,
	swatch: Swatch,
	width: int = PANEL_BORDER_WIDTH
) -> void:
	if control == null:
		return
	var src := _theme_stylebox(control, "panel")
	var box: StyleBoxFlat
	if src is StyleBoxFlat:
		box = (src as StyleBoxFlat).duplicate() as StyleBoxFlat
	else:
		box = panel_style()
	apply_outline(box, show_outline, swatch, width)
	control.add_theme_stylebox_override("panel", box)


static func hud_slot_style(selected: bool = false, empty: bool = false) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = HUD_SLOT_EMPTY if empty else HUD_SLOT_BG
	box.set_corner_radius_all(6)
	if selected:
		box.set_border_width_all(PANEL_BORDER_WIDTH)
		box.border_color = BORDER_DEFAULT
	else:
		box.set_border_width_all(1)
		box.border_color = Color(BORDER_DEFAULT, 0.45)
	return box


static func panel_style(
	bg: Color = BACKGROUND_ELEVATED,
	border: Color = BORDER_DEFAULT
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(PANEL_BORDER_WIDTH)
	box.set_corner_radius_all(PANEL_CORNER_RADIUS)
	return box


static func button_style(
	bg: Color = BUTTON_FILL,
	border: Color = BORDER_DEFAULT
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(PANEL_BORDER_WIDTH)
	box.set_corner_radius_all(BUTTON_CORNER_RADIUS)
	return box
