class_name TestDisplayResolutionPresets
extends RefCounted

const DisplayResolutionPresetsScript := preload("res://scripts/ui/display_resolution_presets.gd")


func run() -> int:
	var failures := 0
	if DisplayResolutionPresetsScript.preset_count() < 4:
		failures += 1
		push_error("Expected several resolution presets")
	var presets := DisplayResolutionPresetsScript.build_presets()
	if not presets.has(Vector2i(1920, 1080)):
		failures += 1
		push_error("Expected 1920x1080 in preset list")
	var native := DisplayResolutionPresetsScript.get_default_monitor_size()
	var uhd := DisplayResolutionPresetsScript.UHD_4K
	var uhd_viable := DisplayResolutionPresetsScript.is_viable_on_display(uhd, native)
	if uhd_viable:
		if not DisplayResolutionPresetsScript.includes_uhd_4k():
			failures += 1
			push_error("Expected 3840x2160 (4K) in preset list")
	elif DisplayResolutionPresetsScript.includes_uhd_4k():
		failures += 1
		push_error("Expected 4K absent when native cannot fit it")
	if presets.size() > 1 and presets[0].x * presets[0].y < presets[1].x * presets[1].y:
		failures += 1
		push_error("Expected presets sorted largest first")
	if DisplayResolutionPresetsScript.format_label(Vector2i(1280, 720)) != "1280 x 720":
		failures += 1
		push_error("Expected formatted resolution label")
	if DisplayResolutionPresetsScript.format_label(Vector2i(3840, 2160)) != "3840 x 2160 (4K)":
		failures += 1
		push_error("Expected 4K preset label")
	var normalized := DisplayResolutionPresetsScript.normalize_size(Vector2i(9999, 8888))
	if normalized != DisplayResolutionPresetsScript.get_default_monitor_size():
		failures += 1
		push_error("Expected unknown resolutions to fall back to native default")
	if DisplayResolutionPresetsScript.clamp_to_screen(
		Vector2i(3840, 2160), Vector2i(1920, 1080)
	) != Vector2i(1920, 1080):
		failures += 1
		push_error("Expected clamp_to_screen to cap at monitor size")
	if not is_equal_approx(
		DisplayResolutionPresetsScript.compute_scaling_3d_scale(
			Vector2i(1920, 1080), Vector2i(3840, 2160)
		),
		0.5
	):
		failures += 1
		push_error("Expected 1080p on 4K fullscreen to use 0.5 3D scale")
	if not is_equal_approx(
		DisplayResolutionPresetsScript.compute_scaling_3d_scale(
			Vector2i(1920, 1080), Vector2i(1920, 1080)
		),
		1.0
	):
		failures += 1
		push_error("Expected matching render/output sizes to use 1.0 3D scale")
	if not is_equal_approx(
		DisplayResolutionPresetsScript.compute_scaling_3d_scale(
			Vector2i(3840, 2160), Vector2i(1920, 1080)
		),
		1.0
	):
		failures += 1
		push_error("Expected oversize render target to clamp 3D scale at 1.0")
	failures += _test_windowed_size_leaves_room_for_decorations()
	failures += _test_saved_size_falls_back_when_display_cannot_fit()
	failures += _test_presets_do_not_exceed_native()
	return failures


## A 1080-tall client area on a 1080 screen hides the bottom of the HUD behind
## the taskbar, because the title bar pushes the client area down.
func _test_windowed_size_leaves_room_for_decorations() -> int:
	var failures := 0
	## 1920x1080 screen, 40px taskbar, 31px title bar + 2px border.
	var fitted := DisplayResolutionPresetsScript.fit_client_to_work_area(
		Vector2i(1920, 1080), Vector2i(1920, 1040), Vector2i(2, 33)
	)
	if fitted != Vector2i(1918, 1007):
		failures += 1
		push_error(
			"Expected native windowed size to shrink below the work area, got %s"
			% str(fitted)
		)
	var small := DisplayResolutionPresetsScript.fit_client_to_work_area(
		Vector2i(1280, 720), Vector2i(1920, 1040), Vector2i(2, 33)
	)
	if small != Vector2i(1280, 720):
		failures += 1
		push_error("Expected a resolution that already fits to stay untouched")
	return failures


## A 4K save from another monitor must not keep 4K on a 1080p panel.
func _test_saved_size_falls_back_when_display_cannot_fit() -> int:
	var failures := 0
	var native_1080 := Vector2i(1920, 1080)
	if not DisplayResolutionPresetsScript.is_viable_on_display(Vector2i(1280, 720), native_1080):
		failures += 1
		push_error("Expected 720p to be viable on 1080p")
	if not DisplayResolutionPresetsScript.is_viable_on_display(Vector2i(1920, 1080), native_1080):
		failures += 1
		push_error("Expected native size to be viable on itself")
	if DisplayResolutionPresetsScript.is_viable_on_display(Vector2i(3840, 2160), native_1080):
		failures += 1
		push_error("Expected 4K not to be viable on 1080p")
	if DisplayResolutionPresetsScript.is_viable_on_display(Vector2i(0, 0), native_1080):
		failures += 1
		push_error("Expected a zero size not to be viable")
	if (
		DisplayResolutionPresetsScript.resolve_saved_window_size(Vector2i(3840, 2160), native_1080)
		!= native_1080
	):
		failures += 1
		push_error("Expected an oversized save to fall back to native")
	if (
		DisplayResolutionPresetsScript.resolve_saved_window_size(Vector2i(1280, 720), native_1080)
		!= Vector2i(1280, 720)
	):
		failures += 1
		push_error("Expected a fitting save to be kept")
	if (
		DisplayResolutionPresetsScript.resolve_saved_window_size(
			Vector2i(2560, 1440), Vector2i(3840, 2160)
		)
		!= Vector2i(2560, 1440)
	):
		failures += 1
		push_error("Expected a smaller save to stay when moving to a larger display")
	if (
		DisplayResolutionPresetsScript.resolve_saved_window_size(Vector2i(0, 0), Vector2i(2560, 1440))
		!= Vector2i(2560, 1440)
	):
		failures += 1
		push_error("Expected a missing size to use native")
	if (
		DisplayResolutionPresetsScript.resolve_saved_window_size(Vector2i(9999, 8888), native_1080)
		!= native_1080
	):
		failures += 1
		push_error("Expected an unknown size to use native")
	return failures


## Dropdown sizes must fit this panel; native itself is always listed.
func _test_presets_do_not_exceed_native() -> int:
	var failures := 0
	var native := DisplayResolutionPresetsScript.get_default_monitor_size()
	var presets := DisplayResolutionPresetsScript.build_presets()
	if not presets.has(native):
		failures += 1
		push_error("Expected native %s in preset list" % str(native))
	for size in presets:
		if size == native:
			continue
		if size.x > native.x or size.y > native.y:
			failures += 1
			push_error(
				"Expected no preset larger than native %s, got %s" % [str(native), str(size)]
			)
			break
	return failures
