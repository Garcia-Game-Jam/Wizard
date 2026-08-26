class_name DisplayResolutionPresets
extends RefCounted

## Window resolution presets for the settings dropdown.

const DEFAULT_SIZE := Vector2i(1920, 1080)
const UHD_4K := Vector2i(3840, 2160)
const MIN_SIZE := Vector2i(640, 360)

const STANDARD_PRESETS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	DEFAULT_SIZE,
	Vector2i(2560, 1440),
	UHD_4K,
]

## Back-compat alias for tests and callers that read the static list.
const PRESETS := STANDARD_PRESETS


## The desktop resolution, reported as-is. Godot allows hidpi by default, so
## screen_get_size() is already in physical pixels and scaling it by DPI
## double-counts. Snapping to the 16:9 list is also wrong: it reports a native
## resolution the monitor does not have on 16:10, ultrawide, and 3:2 panels.
static func get_default_monitor_size() -> Vector2i:
	if DisplayServer.get_name() == "headless":
		return DEFAULT_SIZE
	var screen_id := DisplayServer.get_primary_screen()
	var native := DisplayServer.screen_get_size(screen_id)
	if native.x <= 0 or native.y <= 0:
		return DEFAULT_SIZE
	return native


static func build_presets(include_size: Vector2i = Vector2i.ZERO) -> Array[Vector2i]:
	var presets: Array[Vector2i] = []
	var native := get_default_monitor_size()
	_add_unique_preset(presets, native)
	if (
		include_size.x > 0
		and include_size.y > 0
		and is_viable_on_display(include_size, native)
	):
		_add_unique_preset(presets, include_size)
	for size in STANDARD_PRESETS:
		if is_viable_on_display(size, native):
			_add_unique_preset(presets, size)
	return _sort_presets_descending(presets)


static func preset_count() -> int:
	return build_presets().size()


static func get_preset(index: int, include_size: Vector2i = Vector2i.ZERO) -> Vector2i:
	var presets := build_presets(include_size)
	if index < 0 or index >= presets.size():
		return get_default_monitor_size()
	return presets[index]


static func format_label(size: Vector2i) -> String:
	var label := "%d x %d" % [size.x, size.y]
	if size == UHD_4K:
		return label + " (4K)"
	if size == get_default_monitor_size():
		return label + " (Native)"
	return label


static func find_preset_index(size: Vector2i, include_size: Vector2i = Vector2i.ZERO) -> int:
	var presets := build_presets(include_size)
	for i in presets.size():
		if presets[i] == size:
			return i
	return find_default_preset_index(include_size)


static func find_default_preset_index(include_size: Vector2i = Vector2i.ZERO) -> int:
	return find_preset_index(get_default_monitor_size(), include_size)


static func normalize_size(size: Vector2i) -> Vector2i:
	# Do not pass `size` as include_size — that would invent a preset for any value.
	var native := get_default_monitor_size()
	var presets := build_presets()
	for preset in presets:
		if preset == size:
			if not is_viable_on_display(size, native):
				return native
			return size
	return native


## True when `size` can be shown on `native` without exceeding the panel.
static func is_viable_on_display(size: Vector2i, native: Vector2i) -> bool:
	if size.x < MIN_SIZE.x or size.y < MIN_SIZE.y:
		return false
	if native.x <= 0 or native.y <= 0:
		return true
	return size.x <= native.x and size.y <= native.y


## First-run and migrated saves: keep a fitting size, otherwise use native.
static func resolve_saved_window_size(saved: Vector2i, native: Vector2i) -> Vector2i:
	var fallback := native
	if fallback.x < MIN_SIZE.x or fallback.y < MIN_SIZE.y:
		fallback = DEFAULT_SIZE
	if saved.x <= 0 or saved.y <= 0:
		return fallback
	## Known presets, not build_presets() — that list is filtered to this display.
	var matched := saved == fallback
	for preset in STANDARD_PRESETS:
		if preset == saved:
			matched = true
			break
	if not matched:
		return fallback
	if not is_viable_on_display(saved, fallback):
		return fallback
	return saved


static func includes_uhd_4k() -> bool:
	return build_presets().has(UHD_4K)


static func _sort_presets_descending(presets: Array[Vector2i]) -> Array[Vector2i]:
	var sorted := presets.duplicate()
	sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var area_a := a.x * a.y
		var area_b := b.x * b.y
		if area_a == area_b:
			return a.x > b.x
		return area_a > area_b
	)
	return sorted


static func clamp_to_screen(size: Vector2i, screen_size: Vector2i) -> Vector2i:
	if screen_size.x <= 0 or screen_size.y <= 0:
		return size
	return Vector2i(mini(size.x, screen_size.x), mini(size.y, screen_size.y))


## Largest client area that still fits the desktop work area once the title bar
## and borders are added. Sizing a window's client area to the full screen puts
## its bottom edge under the taskbar, which clips the bottom of the HUD.
static func fit_client_to_work_area(
	size: Vector2i,
	work_area: Vector2i,
	decorations: Vector2i
) -> Vector2i:
	if work_area.x <= 0 or work_area.y <= 0:
		return size
	var available := Vector2i(
		maxi(work_area.x - maxi(decorations.x, 0), MIN_SIZE.x),
		maxi(work_area.y - maxi(decorations.y, 0), MIN_SIZE.y)
	)
	return clamp_to_screen(size, available)


## 3D render scale so the chosen resolution fills the output without upscaling past 1.0.
static func compute_scaling_3d_scale(render_size: Vector2i, output_size: Vector2i) -> float:
	if render_size.x <= 0 or render_size.y <= 0:
		return 1.0
	if output_size.x <= 0 or output_size.y <= 0:
		return 1.0
	var scale_x := float(render_size.x) / float(output_size.x)
	var scale_y := float(render_size.y) / float(output_size.y)
	return clampf(minf(scale_x, scale_y), 0.25, 1.0)


static func _add_unique_preset(presets: Array[Vector2i], size: Vector2i) -> void:
	for existing in presets:
		if existing == size:
			return
	presets.append(size)
