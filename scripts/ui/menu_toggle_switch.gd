@tool
class_name MenuToggleSwitch
extends CheckButton

## Pill switch only — no button panel. Colors are per-instance palette swatches.
## Drawn with canvas primitives; the base CheckButton chrome is blanked once in _ready.

const DEFAULT_PILL_SIZE := Vector2i(40, 20)
const _OUTLINE_WIDTH := 1
const _THUMB_SLIDE_TIME := 0.12

@export var pill_size: Vector2i = DEFAULT_PILL_SIZE:
	set(value):
		var next := Vector2i(maxi(value.x, 8), maxi(value.y, 8))
		if next == pill_size:
			return
		pill_size = next
		_refresh()

@export var on_swatch: UiPalette.Swatch = UiPalette.Swatch.MIST:
	set(value):
		if value == on_swatch:
			return
		on_swatch = value
		_refresh()

@export var off_swatch: UiPalette.Swatch = UiPalette.Swatch.INK:
	set(value):
		if value == off_swatch:
			return
		off_swatch = value
		_refresh()

@export var thumb_swatch: UiPalette.Swatch = UiPalette.Swatch.SNOW_WHITE:
	set(value):
		if value == thumb_swatch:
			return
		thumb_swatch = value
		_refresh()

## 0 = thumb parked left (off), 1 = parked right (on).
var _thumb_t: float = 0.0
var _thumb_tween: Tween

## Reused across redraws — the thumb tween repaints every frame while it slides.
var _track_box := StyleBoxFlat.new()
var _thumb_box := StyleBoxFlat.new()


func _ready() -> void:
	_blank_button_chrome()
	_thumb_t = 1.0 if button_pressed else 0.0
	if not toggled.is_connected(_on_toggled):
		toggled.connect(_on_toggled)
	_refresh()


## One-shot: the stock CheckButton panel and check glyph must not draw under the pill.
## Runs only in _ready — theme overrides re-emit NOTIFICATION_THEME_CHANGED, so doing
## this on every property change would recurse.
func _blank_button_chrome() -> void:
	text = ""
	flat = true
	add_theme_constant_override("h_separation", 0)
	var empty := StyleBoxEmpty.new()
	for style_name in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		add_theme_stylebox_override(style_name, empty)
	var blank := _blank_icon()
	for icon_name in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]:
		add_theme_icon_override(icon_name, blank)


static func _blank_icon() -> Texture2D:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


func _refresh() -> void:
	if not is_node_ready():
		return
	custom_minimum_size = Vector2(pill_size)
	queue_redraw()


func _on_toggled(is_on: bool) -> void:
	var target := 1.0 if is_on else 0.0
	if _thumb_tween != null and _thumb_tween.is_valid():
		_thumb_tween.kill()
	if Engine.is_editor_hint():
		_set_thumb_t(target)
		return
	_thumb_tween = create_tween()
	_thumb_tween.tween_method(_set_thumb_t, _thumb_t, target, _THUMB_SLIDE_TIME)


func _set_thumb_t(value: float) -> void:
	_thumb_t = value
	queue_redraw()


## StyleBoxFlat rounds and antialiases the whole silhouette in one pass. Compositing the
## pill by hand from circles plus a rect cannot: the caps get an antialiased edge, the
## straight span does not, and stacking a second shape for the border blurs the caps.
func _draw() -> void:
	var pill := Rect2(Vector2.ZERO, Vector2(pill_size))
	var fade := 0.45 if disabled else 1.0
	var track := UiPalette.swatch_color(off_swatch).lerp(
		UiPalette.swatch_color(on_swatch), _thumb_t
	)
	track.a *= fade
	_track_box.bg_color = track
	_track_box.set_corner_radius_all(int(pill.size.y * 0.5))
	var outline := UiPalette.HONEY_BRONZE
	outline.a *= fade
	_track_box.border_color = outline
	_track_box.set_border_width_all(_OUTLINE_WIDTH)
	_track_box.draw(get_canvas_item(), pill)
	_draw_thumb(pill, fade)


func _draw_thumb(pill: Rect2, fade: float) -> void:
	var inset := float(_OUTLINE_WIDTH) + 1.0
	var diameter := maxf(pill.size.y - inset * 2.0, 2.0)
	var thumb := UiPalette.swatch_color(thumb_swatch)
	thumb.a *= fade
	_thumb_box.bg_color = thumb
	_thumb_box.set_corner_radius_all(int(diameter * 0.5))
	var travel := maxf(pill.size.x - inset * 2.0 - diameter, 0.0)
	var origin := Vector2(inset + travel * _thumb_t, inset)
	_thumb_box.draw(get_canvas_item(), Rect2(origin, Vector2(diameter, diameter)))
