class_name InputRebindStore
extends RefCounted

## Serialize, apply, reset, and conflict-scan catalog InputMap binds.
## One managed key/mouse event per action.

const CatalogScript := preload("res://scripts/ui/keybinds/input_rebind_catalog.gd")


static func pack_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key := event as InputEventKey
		return {
			"type": "key",
			"physical_keycode": int(key.physical_keycode),
			"alt": key.alt_pressed,
			"shift": key.shift_pressed,
			"ctrl": key.ctrl_pressed,
			"meta": key.meta_pressed,
		}
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		return {"type": "mouse", "button_index": int(mouse.button_index)}
	return {}


static func unpack_event(data: Dictionary) -> InputEvent:
	if data.is_empty():
		return null
	var kind := str(data.get("type", ""))
	if kind == "key":
		var key := InputEventKey.new()
		key.physical_keycode = int(data.get("physical_keycode", 0)) as Key
		key.alt_pressed = bool(data.get("alt", false))
		key.shift_pressed = bool(data.get("shift", false))
		key.ctrl_pressed = bool(data.get("ctrl", false))
		key.meta_pressed = bool(data.get("meta", false))
		return key
	if kind == "mouse":
		var mouse := InputEventMouseButton.new()
		mouse.button_index = int(data.get("button_index", 0)) as MouseButton
		return mouse
	return null


static func is_managed_event(event: InputEvent) -> bool:
	return event is InputEventKey or event is InputEventMouseButton


static func fingerprint_packed(packed: Dictionary) -> String:
	var kind := str(packed.get("type", ""))
	if kind == "key":
		return "k:%s:%s:%s:%s:%s" % [
			int(packed.get("physical_keycode", 0)),
			int(bool(packed.get("alt", false))),
			int(bool(packed.get("shift", false))),
			int(bool(packed.get("ctrl", false))),
			int(bool(packed.get("meta", false))),
		]
	if kind == "mouse":
		return "m:%s" % int(packed.get("button_index", 0))
	return ""


static func pack_action(action: String) -> Dictionary:
	if not InputMap.has_action(action):
		return {}
	for event in InputMap.action_get_events(action):
		if event == null or not is_managed_event(event):
			continue
		return pack_event(event)
	return {}


static func snapshot_actions(actions: PackedStringArray) -> Dictionary:
	var snap := {}
	for action in actions:
		snap[action] = pack_action(action).duplicate(true)
	return snap


static func snapshot_catalog() -> Dictionary:
	return snapshot_actions(CatalogScript.action_names())


static func apply_packed(action: String, packed: Dictionary) -> void:
	if not InputMap.has_action(action):
		return
	var keep: Array[InputEvent] = []
	for event in InputMap.action_get_events(action):
		if event != null and not is_managed_event(event):
			keep.append(event)
	InputMap.action_erase_events(action)
	for event in keep:
		InputMap.action_add_event(action, event)
	var restored := unpack_event(packed)
	if restored != null:
		InputMap.action_add_event(action, restored)


static func apply_snapshot(snap: Dictionary) -> void:
	for action in snap.keys():
		var packed: Dictionary = snap[action] if snap[action] is Dictionary else {}
		apply_packed(str(action), packed)


static func restore_action_from_defaults(action: String, defaults: Dictionary) -> void:
	var packed: Dictionary = {}
	if defaults.get(action) is Dictionary:
		packed = defaults.get(action)
	apply_packed(action, packed)


static func conflict_action_names(
	actions: PackedStringArray = PackedStringArray()
) -> PackedStringArray:
	var names := actions
	if names.is_empty():
		names = CatalogScript.action_names()
	var by_fp := {}
	for action in names:
		var packed := pack_action(action)
		var fp := fingerprint_packed(packed)
		if fp.is_empty():
			continue
		if not by_fp.has(fp):
			by_fp[fp] = PackedStringArray()
		var group: PackedStringArray = by_fp[fp]
		group.append(action)
		by_fp[fp] = group
	var conflicts: PackedStringArray = []
	for fp in by_fp.keys():
		var group: PackedStringArray = by_fp[fp]
		if group.size() < 2:
			continue
		for action in group:
			if _has_blocking_overlap(str(action), group) and not conflicts.has(action):
				conflicts.append(action)
	return conflicts


static func _has_blocking_overlap(action: String, sharing: PackedStringArray) -> bool:
	for other in sharing:
		var other_name := str(other)
		if other_name == action:
			continue
		if not CatalogScript.is_allowed_bind_overlap(action, other_name):
			return true
	return false
