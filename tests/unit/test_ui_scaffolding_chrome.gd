class_name TestUiScaffoldingChrome
extends RefCounted

## Regression guards for per-instance chrome on the scaffolding widgets.
##
## Two failure modes this locks down:
##   1. Recursion — applying a theme override re-emits NOTIFICATION_THEME_CHANGED, so a
##      widget that repaints from that notification loops until the stack overflows.
##      A loop crashes the headless run outright; the bounded-work case is asserted here.
##   2. Override stacking — get_theme_stylebox() returns the local override once one
##      exists, so a naive repaint duplicates its own override and the widget silently
##      stops tracking the Theme.

const ToggleSwitchScene := preload("res://scenes/ui/scaffolding/toggle_switch.tscn")
const ToggleSliderScene := preload("res://scenes/ui/scaffolding/toggle_slider.tscn")
const MenuButtonScene := preload("res://scenes/ui/scaffolding/menu_button.tscn")
const HudSlotScene := preload("res://scenes/ui/scaffolding/hud_slot.tscn")
const StatusBarScene := preload("res://scenes/ui/scaffolding/status_bar.tscn")
const TitleFlareScene := preload("res://scenes/ui/scaffolding/title_flare.tscn")
const ValueSliderScene := preload("res://scenes/ui/scaffolding/value_slider.tscn")
const LobbyPlayerRowScene := preload("res://scenes/ui/scaffolding/lobby_player_row.tscn")

const BUTTON_STATES := ["normal", "hover", "pressed", "disabled", "focus"]
const SWITCH_ICONS := ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]

const UI_SCRIPT_DIR := "res://scripts/ui"

## Calls that write a theme override, and so re-emit NOTIFICATION_THEME_CHANGED.
const OVERRIDE_WRITE_MARKERS := ["add_theme_", "remove_theme_", "UiPalette.paint_"]

## How far to follow same-file helper calls out of a _notification handler.
const CALL_GRAPH_DEPTH := 3

## One repaint clears and rewrites five button states, so ten notifications is the
## honest ceiling. Anything far above means a repaint is re-triggering itself.
const MAX_THEME_CHANGES_PER_PAINT := 24

## Same idea for a whole widget, where one write can legitimately repaint a few children.
const MAX_THEME_CHANGES_PER_WRITE := 64

## A repaint loop is not infinite — GDScript aborts it at 1024 frames — but every abort
## dumps a full backtrace, so absorbing dozens of them turns a failure into a hang. The
## budgets below are checked after each write so the first breach ends the test.
const MAX_CHURN_MSEC := 3000
const CHURN_ITERATIONS := 25

var _theme_changes := 0


func run(tree: SceneTree) -> int:
	var hazards := _find_repaint_loop_hazards()
	var failures := _report(_describe_hazards(hazards))
	failures += _test_repaint_rereads_theme(tree)
	failures += _test_paint_work_is_bounded(tree)
	if not hazards.is_empty():
		## Instantiating a self-repainting widget buries the run in stack-overflow
		## backtraces, so stop here rather than turning a failure into a hang.
		return failures
	failures += _test_hud_slot_uses_theme(tree)
	failures += _test_toggle_switch_is_not_rasterized(tree)
	failures += _test_theme_label_variations(tree)
	failures += _test_value_slider_features(tree)
	failures += _test_lobby_player_row_voice(tree)
	failures += _test_lobby_player_row_configure_before_enter_tree(tree)
	failures += _test_toggle_slider_options(tree)
	failures += _test_export_churn_terminates(tree)
	return failures


## A widget that repaints from NOTIFICATION_THEME_CHANGED re-enters itself through the
## very override it just wrote. GDScript aborts that at 1024 frames, but each abort dumps
## a full backtrace, so the run dies of paperwork long before an assertion can speak.
## Recognise the shape in source instead, before a single node is built.
func _find_repaint_loop_hazards() -> PackedStringArray:
	var hazards := PackedStringArray()
	for path in _ui_scripts(UI_SCRIPT_DIR):
		var source := _strip_comments(FileAccess.get_file_as_string(path))
		var handler := _function_body(source, "_notification")
		if handler.is_empty() or not handler.contains("NOTIFICATION_THEME_CHANGED"):
			continue
		if _reaches_override_write(source, handler, CALL_GRAPH_DEPTH):
			hazards.append(path)
	return hazards


func _describe_hazards(hazards: PackedStringArray) -> String:
	if hazards.is_empty():
		return ""
	return (
		"%s repaints theme overrides from NOTIFICATION_THEME_CHANGED — the override "
		% ", ".join(hazards)
		+ "re-emits that notification, so this recurses until the stack blows. "
		+ "Repaint from _ready and from export setters instead."
	)


func _reaches_override_write(source: String, body: String, depth: int) -> bool:
	for marker in OVERRIDE_WRITE_MARKERS:
		if body.contains(marker):
			return true
	if depth <= 0:
		return false
	for callee in _local_calls(body):
		var callee_body := _function_body(source, callee)
		if callee_body.is_empty():
			continue
		if _reaches_override_write(source, callee_body, depth - 1):
			return true
	return false


func _local_calls(body: String) -> PackedStringArray:
	var names := PackedStringArray()
	var regex := RegEx.create_from_string("\\b(_[a-z][a-z0-9_]*)\\s*\\(")
	for match_result in regex.search_all(body):
		var name := match_result.get_string(1)
		if not names.has(name):
			names.append(name)
	return names


## Returns everything between `func <name>(` and the next top-level declaration.
func _function_body(source: String, name: String) -> String:
	var lines := source.split("\n")
	var body := PackedStringArray()
	var inside := false
	for line in lines:
		if line.begins_with("func %s(" % name) or line.begins_with("static func %s(" % name):
			inside = true
			continue
		if not inside:
			continue
		if not line.is_empty() and not line[0] in [" ", "\t"]:
			break
		body.append(line)
	return "\n".join(body)


func _strip_comments(source: String) -> String:
	var kept := PackedStringArray()
	for line in source.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		kept.append(line)
	return "\n".join(kept)


func _ui_scripts(dir_path: String) -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	for file_name in dir.get_files():
		if file_name.ends_with(".gd"):
			found.append("%s/%s" % [dir_path, file_name])
	for sub_dir in dir.get_directories():
		found.append_array(_ui_scripts("%s/%s" % [dir_path, sub_dir]))
	return found


## Repainting after a Theme swap must pick up the new Theme, not a stale override.
func _test_repaint_rereads_theme(tree: SceneTree) -> int:
	var button := Button.new()
	button.theme = _button_theme(Color(1, 0, 0))
	tree.root.add_child(button)
	UiPalette.paint_button_outline(button, true, UiPalette.Swatch.BRONZE, 2)
	var problem := ""
	var first := button.get_theme_stylebox("normal") as StyleBoxFlat
	if first == null or first.bg_color != Color(1, 0, 0):
		problem = "First paint should preserve the Theme's background"
	elif first.border_color != UiPalette.HONEY_BRONZE:
		problem = "First paint should apply the bronze outline"
	else:
		button.theme = _button_theme(Color(0, 0, 1))
		UiPalette.paint_button_outline(button, true, UiPalette.Swatch.BRONZE, 2)
		var second := button.get_theme_stylebox("normal") as StyleBoxFlat
		if second == null or second.bg_color != Color(0, 0, 1):
			problem = "Repaint kept a stale override instead of re-reading the Theme"
		elif second.border_color != UiPalette.HONEY_BRONZE:
			problem = "Repaint dropped the outline"
	_discard(tree, button)
	return _report(problem)


func _test_paint_work_is_bounded(tree: SceneTree) -> int:
	var button := Button.new()
	button.theme = _button_theme(Color(1, 0, 0))
	tree.root.add_child(button)
	UiPalette.paint_button_outline(button, true, UiPalette.Swatch.BRONZE, 2)
	_theme_changes = 0
	button.theme_changed.connect(_on_theme_changed)
	UiPalette.paint_button_outline(button, false, UiPalette.Swatch.HEALTH, 2)
	button.theme_changed.disconnect(_on_theme_changed)
	var problem := ""
	if _theme_changes == 0:
		problem = "Expected the repaint to rewrite the button's overrides"
	elif _theme_changes > MAX_THEME_CHANGES_PER_PAINT:
		problem = (
			"One repaint emitted %d theme changes (ceiling %d) — a repaint is feeding itself"
			% [_theme_changes, MAX_THEME_CHANGES_PER_PAINT]
		)
	_discard(tree, button)
	return _report(problem)


func _test_hud_slot_uses_theme(tree: SceneTree) -> int:
	var slot: PanelContainer = HudSlotScene.instantiate()
	tree.root.add_child(slot)
	var problem := ""
	if slot.theme_type_variation != &"HudSlot":
		problem = "hud_slot should use the HudSlot theme variation"
	elif _panel_border_width(slot) <= 0:
		problem = "HudSlot theme variation should paint an outline"
	_discard(tree, slot)
	return _report(problem)


## The pill used to be rasterized pixel-by-pixel into four textures per repaint. It is
## drawn with canvas primitives now; oversized check icons mean the rasterizer is back.
func _test_toggle_switch_is_not_rasterized(tree: SceneTree) -> int:
	var toggle: CheckButton = ToggleSwitchScene.instantiate()
	tree.root.add_child(toggle)
	toggle.set("pill_size", Vector2i(64, 32))
	var problem := ""
	for icon_name in SWITCH_ICONS:
		var icon := toggle.get_theme_icon(icon_name)
		if icon == null:
			continue
		if icon.get_width() > 2 or icon.get_height() > 2:
			problem = (
				"CheckButton '%s' icon is %dx%d — the pill should be drawn, not rasterized"
				% [icon_name, icon.get_width(), icon.get_height()]
			)
			break
	if problem.is_empty() and toggle.custom_minimum_size != Vector2(64, 32):
		problem = "pill_size should drive custom_minimum_size"
	_discard(tree, toggle)
	return _report(problem)


## Hammer every export on every widget, watching the theme-change traffic each write
## produces. A widget that repaints itself from NOTIFICATION_THEME_CHANGED blows its
## budget on the very first write and reports which property tripped it.
func _test_export_churn_terminates(tree: SceneTree) -> int:
	var problem := _churn(tree, MenuButtonScene.instantiate())
	if problem.is_empty():
		problem = _churn(tree, HudSlotScene.instantiate())
	if problem.is_empty():
		problem = _churn(tree, StatusBarScene.instantiate())
	if problem.is_empty():
		problem = _churn(tree, TitleFlareScene.instantiate())
	if problem.is_empty():
		problem = _churn(tree, ToggleSwitchScene.instantiate())
	if problem.is_empty():
		problem = _churn(tree, ToggleSliderScene.instantiate())
	if problem.is_empty():
		problem = _churn(tree, ValueSliderScene.instantiate())
	if problem.is_empty():
		problem = _churn(tree, LobbyPlayerRowScene.instantiate())
	return _report(problem)


func _test_theme_label_variations(tree: SceneTree) -> int:
	var label := Label.new()
	label.theme = load("res://resources/ui/serious_wiz_biz_theme.tres")
	tree.root.add_child(label)
	var problem := ""
	label.theme_type_variation = &"TitleLabel"
	if label.get_theme_color("font_color") != UiPalette.ACCENT_PRIMARY:
		problem = "TitleLabel should resolve to accent primary"
	else:
		label.theme_type_variation = &"MutedLabel"
		if label.get_theme_color("font_color") != UiPalette.TEXT_MUTED:
			problem = "MutedLabel should resolve to muted text"
		else:
			label.theme_type_variation = &"CaptionLabel"
			if label.get_theme_color("font_color") != UiPalette.TEXT_DISABLED:
				problem = "CaptionLabel should resolve to disabled text"
	_discard(tree, label)
	return _report(problem)


func _test_value_slider_features(tree: SceneTree) -> int:
	var slider: HBoxContainer = ValueSliderScene.instantiate()
	tree.root.add_child(slider)
	var problem := ""
	slider.set("min_value", 0.0)
	slider.set("max_value", 2.0)
	slider.set("value_kind", 0)  ## FLOAT
	slider.set("show_as_percent", true)
	slider.set("tick_divisions", 1)
	slider.set("show_tick_labels", true)
	slider.set("snap_to_divisions", true)
	slider.call("set_value_no_signal", 1.0)
	var ticks: Control = slider.get_node("TrackArea/TickMarks")
	var edit: LineEdit = slider.get_node("ValueEdit")
	if not is_equal_approx(float(slider.get("value")), 1.0):
		problem = "value_slider should keep unity at midpoint on a 0–2 range"
	elif edit.text != "100%":
		problem = "value_slider unity (1.0) should show 100%%, got '%s'" % edit.text
	elif int(ticks.get("divisions")) != 1:
		problem = "value_slider tick_divisions=1 should configure one interior divider"
	elif int(slider.get_node("TrackArea/Slider").tick_count) != 0:
		problem = "value_slider should hide native HSlider ticks (drawn into the track)"
	elif not is_equal_approx(float(slider.get_node("TrackArea/Slider").step), 1.0):
		problem = "value_slider with 1 divider on 0–2 should snap in halves (step 1)"
	else:
		slider.set("tick_divisions", 2)
		if not is_equal_approx(float(slider.get_node("TrackArea/Slider").step), 2.0 / 3.0):
			problem = "value_slider with 2 dividers should snap in thirds"
		else:
			slider.set("snap_to_divisions", false)
			slider.call("set_value_no_signal", 1.5)
			if edit.text != "150%":
				problem = "value_slider boost past unity should show 150%%, got '%s'" % edit.text
			else:
				edit.text = "75%"
				edit.text_submitted.emit("75%")
				if not is_equal_approx(float(slider.get("value")), 0.75):
					problem = "value_slider should accept typed percent as unity gain"
				else:
					slider.set("default_value", 1.0)
					slider.call("set_value_no_signal", 0.25)
					slider.call("reset_to_default")
					if not is_equal_approx(float(slider.get("value")), 1.0):
						problem = "value_slider.reset_to_default should apply default_value"
					else:
						slider.call("set_value_no_signal", 1.6)
						slider.call("set_current_as_default")
						if not is_equal_approx(float(slider.get("default_value")), 1.6):
							problem = "value_slider.set_current_as_default should store value"
	_discard(tree, slider)
	return _report(problem)


func _test_lobby_player_row_voice(tree: SceneTree) -> int:
	var row: Control = LobbyPlayerRowScene.instantiate()
	tree.root.add_child(row)
	var problem := ""
	var voice := row.get_node_or_null("MixRow/VoiceButton") as Button
	var mix := row.get_node_or_null("MixRow/MixCaption") as Label
	var slider := row.get_node_or_null("MixRow/VolumeSlider") as HSlider
	var value_edit := row.get_node_or_null("MixRow/VolumeSlider/ValueEdit")
	if mix != null:
		problem = "lobby_player_row should use icons, not Mic/Hear captions"
	elif voice == null or not voice.visible:
		problem = "lobby_player_row should show a mute / speaking button"
	elif row.get_node_or_null("IdentityRow/RoleButtons") != null:
		problem = "lobby_player_row should not show role buttons"
	elif slider == null or not slider.visible:
		problem = "lobby_player_row should show a themed HSlider"
	elif value_edit != null:
		problem = "lobby_player_row should not nest the settings value_slider"
	elif voice.alignment != HORIZONTAL_ALIGNMENT_CENTER:
		problem = "lobby_player_row voice icon should be centered in its rect"
	elif voice.custom_minimum_size != PlayerVoiceChrome.BUTTON_SIZE:
		problem = "lobby_player_row voice icon rect should match the slider height"
	else:
		row.set("voice_kind", 1)  ## PEER
		if voice.text == "Hear" or voice.text == "Mic":
			problem = "lobby_player_row should not put Mic/Hear words on the icon"
		elif not is_equal_approx(slider.max_value, 1.0):
			problem = "lobby_player_row Hear slider should be 0–1"
		else:
			row.set("voice_kind", 0)  ## MICROPHONE
			if not is_equal_approx(slider.max_value, 2.0):
				problem = "lobby_player_row Mic slider should be 0–2"
	_discard(tree, row)
	return _report(problem)


func _test_lobby_player_row_configure_before_enter_tree(tree: SceneTree) -> int:
	var row: Control = LobbyPlayerRowScene.instantiate()
	var problem := ""
	row.call("configure", 1, true, "Host (You)")
	tree.root.add_child(row)
	var name_label := row.get_node_or_null("IdentityRow/NameColumn/NameLabel") as Label
	var slider := row.get_node_or_null("MixRow/VolumeSlider") as HSlider
	if name_label == null or name_label.text != "Host (You)":
		problem = "lobby_player_row.configure before add_child should apply after ready"
	elif slider == null:
		problem = "lobby_player_row should keep its mix slider after deferred configure"
	_discard(tree, row)
	return _report(problem)


func _test_toggle_slider_options(tree: SceneTree) -> int:
	var slider: Control = ToggleSliderScene.instantiate()
	tree.root.add_child(slider)
	var problem := ""
	if int(slider.call("option_count")) != 2:
		problem = "toggle_slider should start with the prefab option list"
	elif str(slider.call("get_option_text", 0)) != "Steam":
		problem = "toggle_slider.get_option_text should return Inspector names"
	elif int(slider.call("find_option", "LAN")) != 1:
		problem = "toggle_slider.find_option should return the named index"
	else:
		slider.call("set_options", PackedStringArray(["Local", "LAN", "Steam"]))
		if int(slider.call("option_count")) != 3:
			problem = "set_options should change option_count"
		elif slider.call("set_selected_text", "Steam", false) != OK:
			problem = "set_selected_text should select a named option"
		elif str(slider.call("get_selected_text")) != "Steam":
			problem = "get_selected_text should match the named selection"
		else:
			slider.call("set_options", PackedStringArray(["Local", "LAN"]))
			if int(slider.call("get_selected")) != 1:
				problem = "shrinking options should clamp selected"
			elif slider.call("set_selected_text", "Missing") == OK:
				problem = "set_selected_text should fail for unknown names"
	_discard(tree, slider)
	return _report(problem)


func _churn(tree: SceneTree, node: Node) -> String:
	tree.root.add_child(node)
	_watch_theme_changes(node)
	var swatches: Array = UiPalette.Swatch.values()
	var deadline := Time.get_ticks_msec() + MAX_CHURN_MSEC
	var last_swatch: int = swatches[0]
	var problem := ""
	for i in CHURN_ITERATIONS:
		last_swatch = swatches[i % swatches.size()]
		problem = _churn_pass(node, i, last_swatch, deadline)
		if not problem.is_empty():
			break
	if problem.is_empty():
		problem = _verify_settled(node, last_swatch)
	_discard(tree, node)
	return problem


func _churn_pass(node: Node, index: int, swatch: int, deadline: int) -> String:
	for write in _churn_writes(index, swatch):
		var property: String = write[0]
		if not (property in node):
			continue
		_theme_changes = 0
		node.set(property, write[1])
		if _theme_changes > MAX_THEME_CHANGES_PER_WRITE:
			return (
				"%s.%s emitted %d theme changes in one write (ceiling %d) — repaint loop"
				% [node.name, property, _theme_changes, MAX_THEME_CHANGES_PER_WRITE]
			)
		if Time.get_ticks_msec() > deadline:
			return (
				"%s.%s blew the %dms churn budget — repaint is doing unbounded work"
				% [node.name, property, MAX_CHURN_MSEC]
			)
	return ""


func _churn_writes(index: int, swatch: int) -> Array:
	return [
		["show_rule", index % 2 == 0],
		["diamond_swatch", swatch],
		["pill_size", Vector2i(32 + index, 16 + index % 8)],
		["slider_size", Vector2i(120 + index, 24 + index % 8)],
		["selected", index % 2],
		[
			"options",
			PackedStringArray(["A", "B"]) if index % 2 == 0 else PackedStringArray(["A", "B", "C"]),
		],
		["tick_divisions", 1 + index % 8],
		["fill_swatch", swatch],
		["max_value", 1.0 + float(index % 5)],
		["min_value", 0.0],
		["value_kind", index % 2],
		["show_as_percent", index % 2 == 0],
		["show_tick_labels", index % 2 == 0],
		["snap_to_divisions", index % 2 == 0],
		["step_size", 0.0 if index % 2 == 0 else 0.05],
		["default_value", float(index % 5) * 0.25],
		["tick_swatch", swatch],
		["tick_label_swatch", swatch],
		["value_field_width", 40 + index % 8],
		["player_name", "You" if index % 2 == 0 else "Player A"],
		["detail_text", "Apprentice loadout"],
		["voice_kind", index % 2],
		["preview_muted", index % 2 == 0],
		["preview_speaking", index % 2 == 1],
	]


## Chrome can be repainted on a child, so count the whole subtree's theme traffic.
func _watch_theme_changes(node: Node) -> void:
	if node is Control:
		(node as Control).theme_changed.connect(_on_theme_changed)
	for child in node.get_children():
		_watch_theme_changes(child)


func _verify_settled(node: Node, last_swatch: int) -> String:
	var label := node.name
	if "fill_swatch" in node and int(node.get("fill_swatch")) != last_swatch:
		return "%s dropped the last fill_swatch it was given" % label
	if "pill_size" in node:
		var pill: Vector2i = node.get("pill_size")
		if node.get("custom_minimum_size") != Vector2(pill):
			return "%s minimum size drifted away from pill_size" % label
	if "slider_size" in node:
		var slider: Vector2i = node.get("slider_size")
		if node.get("custom_minimum_size") != Vector2(slider):
			return "%s minimum size drifted away from slider_size" % label
	return ""


func _button_theme(bg: Color) -> Theme:
	var theme := Theme.new()
	for style_name in BUTTON_STATES:
		var box := StyleBoxFlat.new()
		box.bg_color = bg
		theme.set_stylebox(style_name, "Button", box)
	return theme


func _panel_border_width(control: Control) -> int:
	var box := control.get_theme_stylebox("panel") as StyleBoxFlat
	if box == null:
		return -1
	return box.border_width_left


func _on_theme_changed() -> void:
	_theme_changes += 1


func _discard(tree: SceneTree, node: Node) -> void:
	tree.root.remove_child(node)
	node.queue_free()


func _report(problem: String) -> int:
	if problem.is_empty():
		return 0
	push_error(problem)
	return 1
