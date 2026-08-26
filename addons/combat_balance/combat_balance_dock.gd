@tool
extends Control

## Editor table for authored combat numbers. Edits write back to scenes/resources.

const CatalogScript := preload("res://scripts/combat/combat_balance_catalog.gd")
const WriterScript := preload("res://addons/combat_balance/combat_balance_writer.gd")

var _scroll: ScrollContainer
var _column: VBoxContainer
var _status: Label
var _rebuilding := false
var _spells_by_id: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	var root := VBoxContainer.new()
	root.set_anchors_preset(PRESET_FULL_RECT)
	root.size_flags_horizontal = SIZE_EXPAND_FILL
	root.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(root)
	var bar := HBoxContainer.new()
	root.add_child(bar)
	var refresh := Button.new()
	refresh.text = "Reload from disk"
	refresh.pressed.connect(_rebuild)
	bar.add_child(refresh)
	_status = Label.new()
	_status.size_flags_horizontal = SIZE_EXPAND_FILL
	_status.text = "Edits save to the real scenes and spell resources."
	bar.add_child(_status)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	root.add_child(_scroll)
	_column = VBoxContainer.new()
	_column.size_flags_horizontal = SIZE_EXPAND_FILL
	_scroll.add_child(_column)
	call_deferred("_rebuild")


func _rebuild() -> void:
	_rebuilding = true
	for child in _column.get_children():
		child.queue_free()
	_spells_by_id.clear()
	var spells: Array = []
	var editor_paths := _collect_editor_spell_paths()
	if editor_paths.is_empty():
		spells = CatalogScript.load_all_spell_defs()
	else:
		spells = CatalogScript.load_spell_defs_from_paths(editor_paths)
	if spells.is_empty():
		spells = CatalogScript.load_all_spell_defs()
	for spell in spells:
		var spell_id := str(spell.get("id"))
		if not spell_id.is_empty():
			_spells_by_id[spell_id] = spell
	_add_heading("Health pools")
	_build_health_table()
	_add_heading("Spells")
	_build_spell_table()
	for kit in CatalogScript.monster_spell_kits():
		_add_heading("%s spells" % str(kit["name"]))
		_build_monster_spell_table(kit)
	_rebuilding = false
	if _spells_by_id.is_empty():
		_status.text = "Spells not scanned yet — waiting on the editor filesystem."
	elif _status.text.begins_with("Spells not"):
		_status.text = "Edits save to the real scenes and spell resources."


func reload_if_spells_empty() -> void:
	if _spells_by_id.is_empty():
		_rebuild()


func _collect_editor_spell_paths() -> PackedStringArray:
	if not has_meta("editor_filesystem"):
		return PackedStringArray()
	var fs: EditorFileSystem = get_meta("editor_filesystem") as EditorFileSystem
	if fs == null:
		return PackedStringArray()
	var dir := _find_fs_subdir(fs.get_filesystem(), PackedStringArray(["scenes", "spells"]))
	var out := PackedStringArray()
	_collect_fs_tres(dir, out)
	return out


func _find_fs_subdir(
	dir: EditorFileSystemDirectory, parts: PackedStringArray
) -> EditorFileSystemDirectory:
	var current := dir
	for part in parts:
		if current == null:
			return null
		var next_dir: EditorFileSystemDirectory = null
		for i in current.get_subdir_count():
			var sub := current.get_subdir(i)
			if sub != null and sub.get_name() == part:
				next_dir = sub
				break
		current = next_dir
	return current


func _collect_fs_tres(dir: EditorFileSystemDirectory, out: PackedStringArray) -> void:
	if dir == null:
		return
	if str(dir.get_name()).begins_with("_"):
		return
	for i in dir.get_file_count():
		var path := str(dir.get_file_path(i)).replace("\\", "/")
		if path.ends_with(".tres"):
			out.append(path)
	for i in dir.get_subdir_count():
		_collect_fs_tres(dir.get_subdir(i), out)


func _add_heading(title: String) -> void:
	var label := Label.new()
	label.text = title
	label.theme_type_variation = "HeaderSmall"
	_column.add_child(label)


func _make_grid(columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	_column.add_child(grid)
	return grid


func _header_cell(grid: GridContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	grid.add_child(label)


func _name_cell(grid: GridContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	grid.add_child(label)


func _readonly_cell(grid: GridContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	grid.add_child(label)


func _spin(
	grid: GridContainer,
	value: float,
	step: float,
	max_value: float,
	on_change: Callable
) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = 0.0
	spin.max_value = max_value
	spin.step = step
	spin.allow_greater = true
	spin.value = value
	spin.size_flags_horizontal = SIZE_EXPAND_FILL
	spin.value_changed.connect(
		func(next: float) -> void:
			if _rebuilding:
				return
			on_change.call(next)
	)
	grid.add_child(spin)
	return spin


func _build_health_table() -> void:
	var grid := _make_grid(3)
	_header_cell(grid, "Name")
	_header_cell(grid, "Max HP")
	_header_cell(grid, "Touch DPS")
	_name_cell(grid, "Player")
	_spin(
		grid,
		CatalogScript.player_max_health(),
		1.0,
		1000.0,
		func(next: float) -> void:
			_commit(
				WriterScript.apply_max_health(WriterScript.PLAYER_SCENE, next),
				"Player HP"
			)
	)
	_readonly_cell(grid, "—")
	for row in CatalogScript.monster_roster():
		var display := str(row["name"])
		var path := str(row["path"])
		var node_name := str(row["node"])
		_name_cell(grid, display)
		_spin(
			grid,
			float(row["max_health"]),
			1.0,
			1000.0,
			func(next: float) -> void:
				_commit(
					WriterScript.apply_max_health(path, next),
					"%s HP" % display
				)
		)
		_spin(
			grid,
			float(row["touch_dps"]),
			0.1,
			200.0,
			func(next: float) -> void:
				_commit(
					WriterScript.apply_monster(path, node_name, "touch_damage", next),
					"%s touch" % display
				)
		)


func _build_spell_table() -> void:
	var grid := _make_grid(9)
	_header_cell(grid, "Name")
	_header_cell(grid, "Damage")
	_header_cell(grid, "Cooldown")
	_header_cell(grid, "Charge")
	_header_cell(grid, "Max HP")
	_header_cell(grid, "Regen timeout")
	_header_cell(grid, "Regen/s")
	_header_cell(grid, "Shatter regen ×")
	_header_cell(grid, "DPS")
	for row in CatalogScript.spell_rows(_spells_by_id.values()):
		var spell_id := str(row["id"])
		var display := str(row["name"])
		var is_ward := bool(row.get("is_ward", false))
		_name_cell(grid, display)
		_spin(
			grid,
			float(row["damage"]),
			1.0,
			200.0,
			func(next: float) -> void:
				_commit_spell(spell_id, display, "damage", next)
		)
		_spin(
			grid,
			float(row["cooldown_sec"]),
			0.05,
			30.0,
			func(next: float) -> void:
				_commit_spell(spell_id, display, "cooldown", next)
		)
		_spin(
			grid,
			float(row["charge_sec"]),
			0.05,
			10.0,
			func(next: float) -> void:
				_commit_spell(spell_id, display, "charge", next)
		)
		if is_ward:
			_spin(
				grid,
				float(row["max_health"]),
				1.0,
				400.0,
				func(next: float) -> void:
					_commit_spell(spell_id, display, "max_health", next)
			)
			_spin(
				grid,
				float(row["regen_delay_sec"]),
				0.05,
				10.0,
				func(next: float) -> void:
					_commit_spell(spell_id, display, "regen_delay", next)
			)
			_spin(
				grid,
				float(row["regen_per_sec"]),
				0.5,
				50.0,
				func(next: float) -> void:
					_commit_spell(spell_id, display, "regen_per_sec", next)
			)
			_spin(
				grid,
				float(row["shatter_regen_scale"]),
				1.0,
				8.0,
				func(next: float) -> void:
					_commit_spell(spell_id, display, "shatter", next)
			)
		else:
			_readonly_cell(grid, "—")
			_readonly_cell(grid, "—")
			_readonly_cell(grid, "—")
			_readonly_cell(grid, "—")
		_readonly_cell(grid, "%.1f" % float(row["dps"]))


func _build_monster_spell_table(kit: Dictionary) -> void:
	var grid := _make_grid(9)
	_header_cell(grid, "Name")
	_header_cell(grid, "Damage")
	_header_cell(grid, "Cooldown")
	_header_cell(grid, "Charge")
	_header_cell(grid, "Max HP")
	_header_cell(grid, "Regen timeout")
	_header_cell(grid, "Regen/s")
	_header_cell(grid, "Shatter regen ×")
	_header_cell(grid, "DPS")
	for row in kit["spells"]:
		_add_monster_spell_row(grid, row)


func _add_monster_spell_row(grid: GridContainer, row: Dictionary) -> void:
	var display := str(row["name"])
	var monster_path := str(row["monster_path"])
	var node_name := str(row["node"])
	var ability_id := str(row["id"])
	var damage_kind := str(row.get("damage_kind", ""))
	var damage_path := str(row.get("damage_path", ""))
	var damage_node := str(row.get("damage_node", ""))
	var damage_prop := str(row.get("damage_prop", "hit_damage"))
	var is_ward := bool(row.get("is_ward", false))
	_name_cell(grid, display)
	if damage_kind == "projectile":
		_spin(
			grid,
			float(row["damage"]),
			1.0,
			200.0,
			func(next: float) -> void:
				_commit(
					WriterScript.apply_projectile_damage(damage_path, damage_node, next),
					"%s damage" % display
				)
		)
	elif damage_kind == "ability":
		_spin(
			grid,
			float(row["damage"]),
			0.5,
			200.0,
			func(next: float) -> void:
				_commit(
					WriterScript.apply_monster(monster_path, node_name, damage_prop, next),
					"%s damage" % display
				)
		)
	else:
		_readonly_cell(grid, "%.1f" % float(row["damage"]))
	_spin(
		grid,
		float(row["cooldown_sec"]),
		0.05,
		60.0,
		func(next: float) -> void:
			_commit(
				WriterScript.apply_monster(monster_path, node_name, "cooldown_sec", next),
				"%s cooldown" % display
			)
	)
	_spin(
		grid,
		float(row["charge_sec"]),
		0.05,
		10.0,
		func(next: float) -> void:
			_commit(
				WriterScript.apply_monster(monster_path, node_name, "windup_sec", next),
				"%s charge" % display
			)
	)
	if is_ward:
		_spin(
			grid,
			float(row["max_health"]),
			1.0,
			400.0,
			func(next: float) -> void:
				var ok := false
				if ability_id == "charger_ward":
					ok = WriterScript.apply_charger_ward_block(next)
				elif ability_id == "ash_ward":
					ok = WriterScript.apply_player_ward_block(next)
				_commit(ok, "%s HP" % display)
		)
		_readonly_cell(grid, "%.2f" % float(row["regen_delay_sec"]))
		_readonly_cell(grid, "%.1f" % float(row["regen_per_sec"]))
		_readonly_cell(grid, "—")
	else:
		_readonly_cell(grid, "—")
		_readonly_cell(grid, "—")
		_readonly_cell(grid, "—")
		_readonly_cell(grid, "—")
	_readonly_cell(grid, "%.1f" % float(row["dps"]))


func _commit_spell(spell_id: String, display: String, field: String, value: float) -> void:
	var spell: Resource = _spells_by_id.get(spell_id) as Resource
	if spell == null:
		return
	var ok := false
	match field:
		"damage":
			ok = WriterScript.apply_spell_damage(spell, value)
		"cooldown":
			ok = WriterScript.apply_spell_cooldown(spell, value)
		"charge":
			ok = WriterScript.apply_spell_charge(spell, value)
		"max_health":
			ok = WriterScript.apply_spell_max_health(spell, value)
		"regen_delay":
			ok = WriterScript.apply_spell_regen_delay(spell, value)
		"regen_per_sec":
			ok = WriterScript.apply_spell_regen_per_sec(spell, value)
		"shatter":
			ok = WriterScript.apply_spell_shatter_scale(spell, value)
	_commit(ok, "%s %s" % [display, field])


func _commit(ok: bool, label: String) -> void:
	if ok:
		_status.text = "Saved %s" % label
		var filesystem: Object = get_meta("editor_filesystem") if has_meta("editor_filesystem") else null
		WriterScript.rescan_filesystem(filesystem)
	else:
		_status.text = "Could not save %s" % label
