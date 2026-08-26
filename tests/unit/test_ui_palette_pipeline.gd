class_name TestUiPalettePipeline
extends RefCounted

## Guards the token pipeline: palette.json -> UiPalette -> baked Theme resource.
## These three are hand-synced, so drift between them is silent without a test.

const PALETTE_JSON_PATH := "res://resources/ui/palette.json"

## Representative styleboxes that must survive a palette edit + theme rebuild.
const CHECKED_STYLEBOXES := [
	["normal", "Button"],
	["normal", "ColorPickerButton"],
	["hover", "Button"],
	["pressed", "Button"],
	["panel", "PanelContainer"],
	["panel", "HudSlot"],
	["background", "ProgressBar"],
	["fill", "ProgressBar"],
	["fill", "HealthBar"],
]

## Representative theme colors sourced from UiPalette tokens.
const CHECKED_COLORS := [
	["font_color", "Label"],
	["font_color", "Button"],
	["font_disabled_color", "Button"],
	["font_color", "TitleLabel"],
	["font_color", "MutedLabel"],
	["font_color", "CaptionLabel"],
]


func run() -> int:
	var failures := 0
	failures += _test_every_swatch_resolves()
	failures += _test_json_matches_tokens()
	failures += _test_baked_theme_matches_palette()
	return failures


## palette.json color id -> Swatch. Adding a swatch without extending this map fails.
func _swatch_by_json_id() -> Dictionary:
	return {
		"ink_black": UiPalette.Swatch.INK,
		"dark_amethyst": UiPalette.Swatch.AMETHYST,
		"prussian_blue": UiPalette.Swatch.PRUSSIAN,
		"hunter_green": UiPalette.Swatch.HUNTER,
		"honey_bronze": UiPalette.Swatch.BRONZE,
		"snow": UiPalette.Swatch.SNOW_WHITE,
		"health_crimson": UiPalette.Swatch.HEALTH,
		"mist": UiPalette.Swatch.MIST,
	}


## swatch_color() ends in a catch-all that returns Ink. A new enum entry without its own
## match arm silently paints everything black, so prove each one resolves distinctly.
func _test_every_swatch_resolves() -> int:
	var problem := ""
	for swatch_name in UiPalette.Swatch.keys():
		var swatch: UiPalette.Swatch = UiPalette.Swatch[swatch_name]
		if swatch == UiPalette.Swatch.INK:
			continue
		if UiPalette.swatch_color(swatch) == UiPalette.INK_BLACK:
			problem = (
				"Swatch.%s falls through to Ink — add a swatch_color() arm for it"
				% swatch_name
			)
			break
	return _report(problem)


func _test_json_matches_tokens() -> int:
	var text := FileAccess.get_file_as_string(PALETTE_JSON_PATH)
	if text.is_empty():
		return _report("Could not read %s" % PALETTE_JSON_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _report("%s did not parse as a JSON object" % PALETTE_JSON_PATH)
	var mapping := _swatch_by_json_id()
	var colors: Array = (parsed as Dictionary).get("colors", [])
	var problem := ""
	var matched := 0
	for entry_variant in colors:
		var entry: Dictionary = entry_variant
		var color_id := str(entry.get("id", ""))
		if not mapping.has(color_id):
			problem = "palette.json color '%s' has no UiPalette.Swatch" % color_id
			break
		var swatch: UiPalette.Swatch = mapping[color_id]
		var expected := str(entry.get("hex", "")).to_lower()
		var actual := UiPalette.swatch_color(swatch).to_html(false).to_lower()
		if expected != actual:
			problem = (
				"Swatch '%s' is #%s in ui_palette.gd but #%s in palette.json"
				% [color_id, actual, expected]
			)
			break
		matched += 1
	if problem.is_empty() and matched != mapping.size():
		problem = (
			"palette.json defines %d of the %d mapped swatches"
			% [matched, mapping.size()]
		)
	return _report(problem)


## The .tres is generated, so a palette edit without a rebuild leaves the UI stale.
func _test_baked_theme_matches_palette() -> int:
	var saved: Theme = load(UiThemeBuilder.THEME_PATH) as Theme
	if saved == null:
		return _report("Missing baked theme at %s" % UiThemeBuilder.THEME_PATH)
	var fresh := UiThemeBuilder.build()
	var problem := _compare_styleboxes(saved, fresh)
	if problem.is_empty():
		problem = _compare_colors(saved, fresh)
	if problem.is_empty():
		return 0
	push_error("%s — rerun tools/generate_ui_theme.gd" % problem)
	return 1


func _compare_styleboxes(saved: Theme, fresh: Theme) -> String:
	for pair in CHECKED_STYLEBOXES:
		var style_name: String = pair[0]
		var type_name: String = pair[1]
		var baked := saved.get_stylebox(style_name, type_name) as StyleBoxFlat
		var built := fresh.get_stylebox(style_name, type_name) as StyleBoxFlat
		if baked == null or built == null:
			return "Theme %s/%s is missing or not a StyleBoxFlat" % [type_name, style_name]
		if baked.bg_color != built.bg_color:
			return (
				"Theme %s/%s background is #%s, palette says #%s"
				% [
					type_name,
					style_name,
					baked.bg_color.to_html(false),
					built.bg_color.to_html(false),
				]
			)
		if baked.border_color != built.border_color:
			return (
				"Theme %s/%s border is #%s, palette says #%s"
				% [
					type_name,
					style_name,
					baked.border_color.to_html(false),
					built.border_color.to_html(false),
				]
			)
	return ""


func _compare_colors(saved: Theme, fresh: Theme) -> String:
	for pair in CHECKED_COLORS:
		var color_name: String = pair[0]
		var type_name: String = pair[1]
		var baked := saved.get_color(color_name, type_name)
		var built := fresh.get_color(color_name, type_name)
		if baked != built:
			return (
				"Theme %s/%s is #%s, palette says #%s"
				% [type_name, color_name, baked.to_html(), built.to_html()]
			)
	return ""


func _report(problem: String) -> int:
	if problem.is_empty():
		return 0
	push_error(problem)
	return 1
