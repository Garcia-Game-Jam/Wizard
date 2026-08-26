class_name SpellWordBanner
extends Control

## Invisible banner: typewriter-reveals spell words between aim and hotbar.

const CHAR_INTERVAL_SEC := 0.03
const HOLD_AFTER_REVEAL_SEC := 0.9
const SERIF_FONT_PATH := "res://assets/fonts/LibreBaskerville-Regular.otf"
const FONT_SIZE := 68
## Opaque white glyphs; dark outline so they read on bright or dark ground.
const DEFAULT_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.9)
## Place text 40% of the way from screen-center aim toward the hotbar mid.
const AIM_TO_HOTBAR_T := 0.40
const HOTBAR_MID_FROM_BOTTOM_PX := 80.0
const BAND_HALF_HEIGHT_PX := 44.0

var _full_text: String = ""
var _reveal_tween: Tween
var _serif_font: FontFile

@onready var _label: Label = $SpellWordLabel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 64
	_ensure_aim_hotbar_layout()
	_apply_label_style()
	if _label != null:
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label.text = ""
	## Draw above runtime hotbar / casting panel siblings.
	call_deferred("_bring_to_front")
	if not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)


func _on_viewport_size_changed() -> void:
	_ensure_aim_hotbar_layout()


func reveal(text: String, color: Color = DEFAULT_COLOR) -> void:
	_full_text = text.strip_edges()
	_kill_tween()
	_bring_to_front()
	if _label == null:
		return
	var ink := color
	if ink.a < 0.99:
		ink.a = 1.0
	_label.add_theme_color_override("font_color", ink)
	_label.visible = true
	_label.text = ""
	if _full_text.is_empty():
		return
	## Start tween on this node so it keeps ticking with HUD process mode.
	_reveal_tween = create_tween()
	_reveal_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var n := _full_text.length()
	for i in n:
		var slice := _full_text.substr(0, i + 1)
		_reveal_tween.tween_callback(_set_label_text.bind(slice))
		if i < n - 1:
			_reveal_tween.tween_interval(CHAR_INTERVAL_SEC)
	_reveal_tween.tween_interval(HOLD_AFTER_REVEAL_SEC)
	_reveal_tween.tween_callback(clear)


func clear() -> void:
	_kill_tween()
	_full_text = ""
	if _label != null:
		_label.text = ""


func _ensure_aim_hotbar_layout() -> void:
	## Center-anchored; shift down 25% of the gap from aim crosshair to hotbar.
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -420.0
	offset_right = 420.0
	var viewport_h := get_viewport_rect().size.y
	if viewport_h <= 1.0:
		viewport_h = 1080.0
	var aim_y := viewport_h * 0.5
	var inventory_y := viewport_h - HOTBAR_MID_FROM_BOTTOM_PX
	var target_y := lerpf(aim_y, inventory_y, AIM_TO_HOTBAR_T)
	var dy := target_y - aim_y
	offset_top = dy - BAND_HALF_HEIGHT_PX
	offset_bottom = dy + BAND_HALF_HEIGHT_PX
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH


func _apply_label_style() -> void:
	if _label == null:
		return
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_color_override("font_color", DEFAULT_COLOR)
	_label.add_theme_constant_override("outline_size", 6)
	_label.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	_apply_serif_font()


func _apply_serif_font() -> void:
	if _label == null:
		return
	## FileAccess reads the source .otf; ResourceLoader.load() follows the
	## missing .godot/imported remap and yields an empty FreeType face.
	if not FileAccess.file_exists(SERIF_FONT_PATH):
		return
	var font_bytes := FileAccess.get_file_as_bytes(SERIF_FONT_PATH)
	if not _is_loadable_font_bytes(font_bytes):
		push_warning("SpellWordBanner: serif font is missing or invalid; using default")
		return
	var loaded := FontFile.new()
	var err := loaded.load_dynamic_font(SERIF_FONT_PATH)
	if err != OK:
		push_warning("SpellWordBanner: failed to load serif font (%s)" % err)
		return
	## Never call get_height / FreeType on an empty face — that ERRORs first.
	if loaded.data.is_empty():
		push_warning("SpellWordBanner: serif font has no data; using default")
		return
	_serif_font = loaded
	_label.add_theme_font_override("font", _serif_font)


func _is_loadable_font_bytes(bytes: PackedByteArray) -> bool:
	if bytes.size() < 4:
		return false
	## TrueType sfnt version 1.0
	if bytes[0] == 0x00 and bytes[1] == 0x01 and bytes[2] == 0x00 and bytes[3] == 0x00:
		return true
	var tag := bytes.slice(0, 4).get_string_from_ascii()
	return tag == "OTTO" or tag == "true" or tag == "wOFF" or tag == "wOF2"


func _bring_to_front() -> void:
	var parent_node := get_parent()
	if parent_node != null:
		parent_node.move_child(self, -1)
	visible = true
	modulate = Color(1, 1, 1, 1)
	self_modulate = Color(1, 1, 1, 1)


func _set_label_text(value: String) -> void:
	if _label != null:
		_label.text = value


func _kill_tween() -> void:
	if _reveal_tween != null and is_instance_valid(_reveal_tween):
		_reveal_tween.kill()
	_reveal_tween = null
