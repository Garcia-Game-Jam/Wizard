@tool
extends Node3D

## Encounter design workshop — author a LevelDefinition (a map id plus an
## ordered sequence of encounters, each with monster spawns and cover
## obstacle positions) against a live preview of the actual arena scene for
## the level's chosen map.
##
## New/Load/Save As for the whole level is the `level` field's own Inspector
## resource picker (the dropdown arrow next to it) — a LevelDefinition IS the
## save file, so that picker gives you those for free, and expanding it in
## the Inspector gives +/- and reorder for its `encounters` array, and each
## encounter's `monsters`/`obstacle_positions` arrays. Nothing here
## reimplements any of that. IMPORTANT: that picker's own "Save" only writes
## whatever is already IN the resource — it does NOT pull in-viewport marker
## drags first. Use the "Save Level" action below for that (it syncs, then
## writes); the Level field's Save is really only for a plain "New Level" ->
## rename -> Save As first-time-to-disk flow.
##
## `selected_encounter_index` picks which encounter's monsters/obstacles show
## as preview markers under EncounterPreview — spheres (color-coded red/
## orange/blue for charger/ember/ash) for monsters, tan boxes for obstacles.
## Click one in the 3D viewport to select it (they're owned by the edited
## scene specifically so they're pickable/draggable, same as any other node —
## plain preview VFX elsewhere in this project, e.g. ward_workspace.gd's
## CastPreview contents, are deliberately NOT owned since nothing there is
## meant to be grabbed and edited; these markers are the opposite case). Drag
## one with the move gizmo, then run "Save Level" (or "Sync Positions From
## Markers" if you just want it committed into `level` without writing the
## file yet — switching encounters also auto-syncs the one you're leaving,
## so a drag never gets silently lost just from changing
## selected_encounter_index). A monster marker also has its own `Kind` and
## `Spawn Animation` fields right there in the Inspector
## (scripts/arena/monster_spawn_marker.gd) — pick charger/ember/ash, or which
## spawn-telegraph effect plays before that monster appears (only
## "Classic Beam" exists so far — scripts/arena/spawn_telegraph_fx.gd), on
## the spawn point itself, and either writes back into the matching
## MonsterSpawnEntry immediately, no separate sync step needed (unlike
## position, neither one is something that fires 60 times a second). "Add
## Monster/Obstacle At Camera Focus" appends a new entry in front of the
## editor camera instead of typing raw coordinates.
##
## To delete, select one or more markers and run "Delete Selected Markers"
## — NOT the viewport's own Delete/Backspace, which only removes the node
## and leaves the underlying `level` entry in place (it'll just reappear the
## next time anything else triggers a preview rebuild).

const ArenaCatalogScript := preload("res://scripts/arena/arena_catalog.gd")
const LevelDefinitionScript := preload("res://scripts/arena/level_definition.gd")
const EncounterDefinitionScript := preload("res://scripts/arena/encounter_definition.gd")
const MonsterSpawnEntryScript := preload("res://scripts/arena/monster_spawn_entry.gd")
const MonsterSpawnMarkerScript := preload("res://scripts/arena/monster_spawn_marker.gd")

const DEFAULT_LEVEL_PATH := "res://scenes/arenas/levels/default_level.tres"
## Matches the PlayerSpawn_0..3 markers already authored in every current
## arena (scenes/arena.tscn, scenes/arenas/arena_bulls.tscn) — created here
## for any future map that's missing them.
const REQUIRED_PLAYER_SPAWNS: Array[Vector3] = [
	Vector3(-4.0, 1.0, 14.0),
	Vector3(4.0, 1.0, 14.0),
	Vector3(-4.0, 1.0, 16.0),
	Vector3(4.0, 1.0, 16.0),
]
const OBSTACLE_MARKER_COLOR := Color(0.6, 0.55, 0.3, 0.9)
const MARKER_RADIUS := 0.5
const CAMERA_FOCUS_DISTANCE := 6.0

@export var level: LevelDefinitionScript:
	set(value):
		level = value
		_last_signature = ""
		_rebuild_map_preview()
		_rebuild_encounter_preview()

@export_range(0, 20, 1, "or_greater") var selected_encounter_index: int = 0:
	set(value):
		## Commit the encounter being LEFT before switching away — otherwise a
		## drag you haven't synced yet is silently discarded the moment the
		## preview rebuilds for the newly-selected encounter, since markers
		## are always regenerated fresh from the resource.
		_sync_positions_from_markers()
		selected_encounter_index = maxi(value, 0)
		_rebuild_encounter_preview()

@export_tool_button("New Level", "Callable")
var new_level_action := _action_new_level
@export_tool_button("Add Encounter", "Callable")
var add_encounter_action := _action_add_encounter
@export_tool_button("Delete Selected Encounter", "Callable")
var delete_encounter_action := _action_delete_selected_encounter
@export_tool_button("Add Monster At Camera Focus", "Callable")
var add_monster_action := _action_add_monster
@export_tool_button("Add Obstacle At Camera Focus", "Callable")
var add_obstacle_action := _action_add_obstacle
@export_tool_button("Sync Positions From Markers", "Callable")
var sync_from_markers_action := _sync_positions_from_markers
@export_tool_button("Delete Selected Markers", "Callable")
var delete_selected_markers_action := _action_delete_selected_markers
@export_tool_button("Save Level", "Callable")
var save_level_action := _action_save_level
@export_tool_button("Refresh Preview", "Callable")
var refresh_action := _refresh_preview

var _last_signature: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	## level's own setter already rebuilt both previews once, during scene
	## instantiation's property application, whenever the scene sets it (the
	## normal case — the .tscn assigns the default level). Only the "freshly
	## added to an empty scene with no level yet" case still needs a kick.
	if level == null:
		var loaded: Resource = (
			load(DEFAULT_LEVEL_PATH) if ResourceLoader.exists(DEFAULT_LEVEL_PATH) else null
		)
		level = (loaded as LevelDefinitionScript) if loaded != null else LevelDefinitionScript.new()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint() or level == null:
		return
	## Editing a field on a nested Resource (level.map_id, an encounter's
	## label, a monster's kind/position, ...) doesn't fire this node's own
	## exported-property setters — Godot has no change notification for
	## that. Poll cheaply instead so those edits still refresh the preview.
	var sig := _signature()
	if sig == _last_signature:
		return
	_last_signature = sig
	_rebuild_map_preview()
	_rebuild_encounter_preview()


func _refresh_preview() -> void:
	_rebuild_map_preview()
	_rebuild_encounter_preview()
	## Must reflect the state just rebuilt FROM, not "unknown" — leaving this
	## at "" made the very next _process() poll see a false "change" (real
	## signature is never empty once a level has encounters) and rebuild
	## AGAIN one frame later, tearing down and recreating every marker a
	## second time right after any action that calls this (Add Monster,
	## Add Obstacle, Delete Selected Markers, ...). That extra, unnecessary
	## rebuild could invalidate a marker the Inspector had just started
	## editing (e.g. picking Kind right after Add Monster) out from under it.
	_last_signature = _signature()


func _signature() -> String:
	if level == null:
		return ""
	var parts := PackedStringArray(
		[level.map_id, str(selected_encounter_index), str(level.encounters.size())]
	)
	var enc := _selected_encounter()
	if enc != null:
		for m in enc.monsters:
			parts.append("%s@%s@%s@%s" % [m.kind, m.position, m.facing_deg, m.spawn_animation])
		for p in enc.obstacle_positions:
			parts.append(str(p))
	return "|".join(parts)


func _selected_encounter() -> EncounterDefinitionScript:
	if level == null or level.encounters.is_empty():
		return null
	var idx := clampi(selected_encounter_index, 0, level.encounters.size() - 1)
	return level.encounters[idx]


## --- Level/encounter actions ---------------------------------------------


func _action_new_level() -> void:
	var fresh := LevelDefinitionScript.new()
	fresh.level_name = "New Level"
	fresh.map_id = ArenaCatalogScript.default_id()
	level = fresh


func _action_add_encounter() -> void:
	if level == null:
		_action_new_level()
	var is_first := level.encounters.is_empty()
	var enc := EncounterDefinitionScript.new()
	enc.label = "Encounter %d" % level.encounters.size()
	level.encounters.append(enc)
	selected_encounter_index = level.encounters.size() - 1
	if is_first:
		_ensure_player_spawns_for_all_maps()
	_refresh_preview()


func _action_delete_selected_encounter() -> void:
	if level == null or level.encounters.is_empty():
		return
	var idx := clampi(selected_encounter_index, 0, level.encounters.size() - 1)
	level.encounters.remove_at(idx)
	selected_encounter_index = clampi(
		selected_encounter_index, 0, maxi(level.encounters.size() - 1, 0)
	)
	_refresh_preview()


func _action_add_monster() -> void:
	var enc := _selected_encounter()
	if enc == null:
		return
	var entry := MonsterSpawnEntryScript.new()
	entry.position = _camera_focus_point()
	enc.monsters.append(entry)
	_refresh_preview()


func _action_add_obstacle() -> void:
	var enc := _selected_encounter()
	if enc == null:
		return
	enc.obstacle_positions.append(_camera_focus_point())
	_refresh_preview()


func _sync_positions_from_markers() -> void:
	var enc := _selected_encounter()
	if enc == null:
		return
	var marker_root := _marker_root()
	for i in enc.monsters.size():
		var marker := marker_root.get_node_or_null("Monster%d" % i) as Node3D
		if marker == null:
			continue
		enc.monsters[i].position = marker.position
		enc.monsters[i].facing_deg = rad_to_deg(marker.rotation.y)
	for i in enc.obstacle_positions.size():
		var marker := marker_root.get_node_or_null("Obstacle%d" % i) as Node3D
		if marker != null:
			enc.obstacle_positions[i] = marker.position
	_last_signature = _signature()


## The one-click "formalize the changes" action: commits every marker's
## current position/facing into `level` (same as Sync Positions From
## Markers) AND actually writes the file to disk — the Level field's own
## Inspector Save button only writes whatever's already IN the resource, so
## a drag you never synced was silently lost even after clicking Save there.
func _action_save_level() -> void:
	if level == null:
		return
	_sync_positions_from_markers()
	if level.resource_path.is_empty():
		push_warning(
			"EncounterDesignWorkshop: this Level has never been saved to a file — use its "
			+ "own Inspector picker (the dropdown arrow next to the Level field) → Save "
			+ "As... once, then Save Level will write to that same file from here on."
		)
		return
	var err := ResourceSaver.save(level, level.resource_path)
	if err != OK:
		push_error("EncounterDesignWorkshop: failed to save %s (%s)" % [level.resource_path, err])


## Deletes by resource index, not by freeing the node — a marker is just a
## view of `level`'s data, so removal has to go through the array or the
## next rebuild (data unchanged) brings the "deleted" marker right back.
func _action_delete_selected_markers() -> void:
	if not Engine.is_editor_hint():
		return
	var enc := _selected_encounter()
	if enc == null:
		return
	var marker_root := _marker_root()
	var monster_indices: Array[int] = []
	var obstacle_indices: Array[int] = []
	for node in EditorInterface.get_selection().get_selected_nodes():
		if not (node is Node3D) or node.get_parent() != marker_root:
			continue
		var node_name := String(node.name)
		if node_name.begins_with("Monster"):
			monster_indices.append(node_name.trim_prefix("Monster").to_int())
		elif node_name.begins_with("Obstacle"):
			obstacle_indices.append(node_name.trim_prefix("Obstacle").to_int())
	## Highest index first, so removing one doesn't shift the rest still
	## queued for removal out from under their recorded index.
	monster_indices.sort()
	monster_indices.reverse()
	for idx in monster_indices:
		if idx >= 0 and idx < enc.monsters.size():
			enc.monsters.remove_at(idx)
	obstacle_indices.sort()
	obstacle_indices.reverse()
	for idx in obstacle_indices:
		if idx >= 0 and idx < enc.obstacle_positions.size():
			enc.obstacle_positions.remove_at(idx)
	_refresh_preview()


func _camera_focus_point() -> Vector3:
	if Engine.is_editor_hint():
		var viewport := EditorInterface.get_editor_viewport_3d(0)
		var cam := viewport.get_camera_3d() if viewport != null else null
		if cam != null:
			return cam.global_position + (-cam.global_transform.basis.z) * CAMERA_FOCUS_DISTANCE
	return Vector3.ZERO


## --- Map scaffolding -------------------------------------------------------


## "when adding the first encounter it should automatically create any
## necessary map features for all maps like all player spawns" — a one-time
## sanity pass across the whole catalog, not just the level's chosen map, so
## no map is left missing spawns just because a level was authored for a
## different one first.
func _ensure_player_spawns_for_all_maps() -> void:
	for id in ArenaCatalogScript.all_ids():
		_ensure_player_spawns_for_map(id)


func _ensure_player_spawns_for_map(map_id: String) -> void:
	var scene_path := ArenaCatalogScript.scene_path_for_id(map_id)
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	var root_instance := packed.instantiate()
	var players := root_instance.get_node_or_null("Players") as Node3D
	var changed := false
	if players == null:
		players = Node3D.new()
		players.name = "Players"
		root_instance.add_child(players)
		players.owner = root_instance
		changed = true
	for i in REQUIRED_PLAYER_SPAWNS.size():
		var spawn_name := "PlayerSpawn_%d" % i
		if players.get_node_or_null(spawn_name) != null:
			continue
		var marker := Marker3D.new()
		marker.name = spawn_name
		marker.position = REQUIRED_PLAYER_SPAWNS[i]
		players.add_child(marker)
		marker.owner = root_instance
		changed = true
	if changed:
		var new_packed := PackedScene.new()
		if new_packed.pack(root_instance) == OK:
			ResourceSaver.save(new_packed, scene_path)
			push_warning(
				"EncounterDesignWorkshop: added missing PlayerSpawn markers to %s" % scene_path
			)
	root_instance.free()


## --- Preview geometry -------------------------------------------------------


func _rebuild_map_preview() -> void:
	var root_node := _preview_root()
	for child in root_node.get_children():
		_free_child(child)
	if level == null or level.map_id.is_empty():
		return
	var scene_path := ArenaCatalogScript.scene_path_for_id(level.map_id)
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	root_node.add_child(packed.instantiate())


func _rebuild_encounter_preview() -> void:
	var marker_root := _marker_root()
	for child in marker_root.get_children():
		_free_child(child)
	var enc := _selected_encounter()
	if enc == null:
		return
	for i in enc.monsters.size():
		var entry := enc.monsters[i]
		var marker := _make_monster_marker(i, entry)
		marker_root.add_child(marker)
		_own_recursive(marker)
	for i in enc.obstacle_positions.size():
		var marker := _make_marker("Obstacle%d" % i, OBSTACLE_MARKER_COLOR, false)
		marker.position = enc.obstacle_positions[i]
		marker_root.add_child(marker)
		_own_recursive(marker)


## kind is set, then _on_kind_changed is wired up after — so the initial
## assignment (which mirrors the resource's current value) never fires a
## write-back into the very entry it was just read from.
func _make_monster_marker(index: int, entry: MonsterSpawnEntryScript) -> Node3D:
	var marker := MonsterSpawnMarkerScript.new()
	marker.name = "Monster%d" % index
	marker.kind = entry.kind
	marker.spawn_animation = entry.spawn_animation
	marker.position = entry.position
	marker.rotation.y = deg_to_rad(entry.facing_deg)
	marker.set("_on_kind_changed", Callable(self, "_on_marker_kind_changed").bind(index))
	marker.set(
		"_on_spawn_animation_changed", Callable(self, "_on_marker_spawn_animation_changed").bind(index)
	)
	return marker


func _on_marker_kind_changed(new_kind: String, index: int) -> void:
	var enc := _selected_encounter()
	if enc == null or index < 0 or index >= enc.monsters.size():
		return
	enc.monsters[index].kind = new_kind
	## Already applied — don't let the next _process() poll see its own
	## change and immediately tear down/rebuild the marker the user is
	## mid-edit on.
	_last_signature = _signature()


func _on_marker_spawn_animation_changed(new_animation: String, index: int) -> void:
	var enc := _selected_encounter()
	if enc == null or index < 0 or index >= enc.monsters.size():
		return
	enc.monsters[index].spawn_animation = new_animation
	_last_signature = _signature()


func _make_marker(marker_name: String, color: Color, sphere: bool) -> Node3D:
	var body := Node3D.new()
	body.name = marker_name
	var mesh_instance := MeshInstance3D.new()
	var mesh: Mesh
	if sphere:
		var sphere_mesh := SphereMesh.new()
		sphere_mesh.radius = MARKER_RADIUS
		sphere_mesh.height = MARKER_RADIUS * 2.0
		mesh = sphere_mesh
	else:
		var box_mesh := BoxMesh.new()
		box_mesh.size = Vector3.ONE * (MARKER_RADIUS * 2.0)
		mesh = box_mesh
	mesh_instance.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.material_override = mat
	body.add_child(mesh_instance)
	return body


## Both preview buckets are stable containers (own their spot in the scene
## tree so they show up in the editor's Scene panel). MapPreview's contents
## (the instanced reference-geometry map) deliberately stay unowned — same
## as ward_workspace.gd's CastPreview bucket — since it's a read-only visual
## reference, never meant to be selected/edited/saved into this .tscn.
## EncounterPreview's markers are the opposite: they're the only way to
## move/delete a monster or obstacle by hand, so those ARE owned (see
## _own_recursive below) despite being rebuilt just as often.
func _preview_root() -> Node3D:
	var node := get_node_or_null("MapPreview") as Node3D
	if node != null:
		return node
	node = Node3D.new()
	node.name = "MapPreview"
	add_child(node)
	_own_if_editor(node)
	return node


func _marker_root() -> Node3D:
	var node := get_node_or_null("EncounterPreview") as Node3D
	if node != null:
		return node
	node = Node3D.new()
	node.name = "EncounterPreview"
	add_child(node)
	_own_if_editor(node)
	return node


func _own_if_editor(node: Node) -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var edited := get_tree().edited_scene_root
	if edited != null:
		node.owner = edited


## Godot's 3D viewport only lets you click-select a node that's owned by the
## edited scene AND every ancestor down to it is too — owning just the
## marker body isn't enough once it has a mesh child, so walk the whole
## subtree. Needed for markers to be selectable/draggable at all; skip for
## content that's meant to stay a read-only visual (see _preview_root).
func _own_recursive(node: Node) -> void:
	_own_if_editor(node)
	for child in node.get_children():
		_own_recursive(child)


## Always immediate, never queue_free() — a rebuild clears a bucket and
## re-adds same-named children in the same call. A deferred free is still
## pending when add_child() runs again moments later, so the new node
## collides with the old (not-yet-actually-gone) one of the same name and
## gets silently auto-renamed instead.
func _free_child(child: Node) -> void:
	child.free()
