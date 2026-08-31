class_name NetRewindableMover
extends RefCounted

## Authors RollbackSynchronizer / TickInterpolator / Input / PredictiveSynchronizer
## from code profiles. Call after the root is in the tree and authority is set.

const NetAuthorityScript := preload("res://scripts/net/net_authority.gd")
const PlayerNetInputScript := preload("res://scripts/net/player_net_input.gd")
const Profiles := preload("res://scripts/net/net_rewindable_profiles.gd")

const HOST_PEER_ID := NetAuthorityScript.HOST_PEER_ID
const INPUT_NAME := "Input"
const RS_NAME := "RollbackSynchronizer"
const TI_NAME := "TickInterpolator"
const PS_NAME := "PredictiveSynchronizer"
const RS_CLASS := "RollbackSynchronizer"
const TI_CLASS := "TickInterpolator"
const PS_CLASS := "PredictiveSynchronizer"


static func apply_playable(root: Node, owner_peer_id: int, local_view: bool = false) -> void:
	if root == null or not root.is_inside_tree():
		return
	_strip_multiplayer_synchronizer(root)
	root.set_multiplayer_authority(HOST_PEER_ID)
	var input := _ensure_input(root)
	if owner_peer_id > 0:
		input.set_multiplayer_authority(owner_peer_id)
	else:
		input.set_multiplayer_authority(root.multiplayer.get_unique_id())
	var rs := _ensure_rollback(
		root,
		_state_paths_for(root, Profiles.PLAYABLE),
		PlayerNetInputScript.net_input_paths(),
		true
	)
	var ti := _ensure_interpolator(root, Profiles.PLAYABLE)
	if local_view and ti != null:
		## Blend XZ/Y between ticks so walk is not 30 Hz. Do not lerp look —
		## that fights mouse. Jump still comes from Input:jump on the tick.
		ti.set("properties", Profiles.local_playable_interpolate_paths())
		if ti.has_method("process_settings"):
			ti.call("process_settings")
	if rs != null and rs.has_method("process_settings"):
		rs.call("process_settings")


static func apply_world_prop(root: Node, profile: String = "") -> void:
	if root == null or not root.is_inside_tree():
		return
	## Persistent props (cover) must not process_settings again — that re-seeds
	## at the original spawn_tick, which is soon outside the history window.
	if rollback_of(root) != null:
		return
	_strip_multiplayer_synchronizer(root)
	root.set_multiplayer_authority(HOST_PEER_ID)
	var resolved := profile
	if resolved.is_empty():
		resolved = Profiles.WORLD_PROP
	var empty_inputs: Array[String] = []
	var rs := _ensure_rollback(
		root,
		_state_paths_for(root, resolved),
		empty_inputs,
		false
	)
	_ensure_interpolator(root, resolved)
	if rs != null:
		rs.set("enable_prediction", false)
		if rs.has_method("process_settings"):
			rs.call("process_settings")


static func apply_projectile(root: Node3D) -> Node:
	if root == null:
		return null
	_strip_multiplayer_synchronizer(root)
	var ps := root.get_node_or_null(PS_NAME)
	if ps == null:
		ps = _instantiate_named(PS_CLASS, PS_NAME)
		if ps != null:
			ps.set("root", root)
			root.add_child(ps)
	if ps == null:
		return null
	ps.set("root", root)
	ps.set("state_properties", Profiles.state_paths(Profiles.PROJECTILE))
	if ps.has_method("process_settings"):
		ps.call("process_settings")
	if ps.has_method("spawn"):
		ps.call("spawn")
	return ps


## Write the node's current pose into history at the live tick and snap
## interpolation. Call after teleporting an already-attached world prop.
static func commit_world_pose(root: Node) -> void:
	if root == null or not root.is_inside_tree():
		return
	if rollback_of(root) == null:
		return
	var tick := _clock_tick()
	if tick < 0:
		return
	var nr := _autoload("NetworkRollback")
	if nr != null and tick < int(nr.get("history_start")):
		return
	var history := _history_server()
	if history != null and history.has_method("push_rollback_state"):
		history.call("push_rollback_state", root, tick)
	var ti := root.get_node_or_null(TI_NAME)
	if ti == null or not ti.has_method("teleport"):
		return
	if ti.has_method("can_interpolate") and not bool(ti.call("can_interpolate")):
		return
	ti.call("teleport")


static func rollback_of(root: Node) -> Node:
	if root == null:
		return null
	return root.get_node_or_null(RS_NAME)


static func predictive_of(root: Node) -> Node:
	if root == null:
		return null
	return root.get_node_or_null(PS_NAME)


static func _ensure_input(root: Node) -> Node:
	var input := root.get_node_or_null(INPUT_NAME)
	if input != null:
		return input
	input = PlayerNetInputScript.new()
	input.name = INPUT_NAME
	root.add_child(input)
	return input


static func _ensure_rollback(
	root: Node,
	state: Array[String],
	inputs: Array[String],
	with_input: bool
) -> Node:
	var rs := root.get_node_or_null(RS_NAME)
	if rs == null:
		rs = _instantiate_named(RS_CLASS, RS_NAME)
		if rs != null:
			rs.set("root", root)
			## Default spawn_tick is -1; _ready would set tick+1, which is outside
			## the history ring and logs "Dropping seeded state". Seed the live tick.
			## NetworkTime.tick, not NetworkRollback.tick — the latter stays on
			## the last sim tick after stop() and poisons the next match.
			var tick := _clock_tick()
			if tick >= 0:
				rs.set("spawn_tick", tick)
			root.add_child(rs)
	if rs == null:
		return null
	rs.set("root", root)
	rs.set("state_properties", state)
	if with_input:
		rs.set("input_properties", inputs)
	else:
		var empty: Array[String] = []
		rs.set("input_properties", empty)
	rs.set("enable_prediction", with_input)
	rs.set("enable_input_broadcast", false)
	return rs


static func _state_paths_for(root: Node, fallback_profile: String) -> Array[String]:
	if root != null and root.has_method("net_state_paths"):
		var raw: Variant = root.call("net_state_paths")
		if raw is Array:
			var typed: Array[String] = []
			for item in raw:
				typed.append(str(item))
			if not typed.is_empty():
				return typed
	return Profiles.state_paths(fallback_profile)


static func _ensure_interpolator(root: Node, profile: String) -> Node:
	var ti := root.get_node_or_null(TI_NAME)
	if ti == null:
		ti = _instantiate_named(TI_CLASS, TI_NAME)
		if ti != null:
			ti.set("root", root)
			root.add_child(ti)
	if ti == null:
		return null
	ti.set("root", root)
	ti.set("properties", Profiles.interpolate_paths(profile))
	if ti.has_method("process_settings"):
		ti.call("process_settings")
	return ti


static func _instantiate_named(class_id: String, node_name: String) -> Node:
	var path := _script_path(class_id)
	if path.is_empty() or not ResourceLoader.exists(path):
		push_error("NetRewindableMover: missing %s" % class_id)
		return null
	var script := load(path) as GDScript
	if script == null:
		push_error("NetRewindableMover: failed to load %s" % class_id)
		return null
	var created := script.new() as Node
	if created == null:
		return null
	created.name = node_name
	return created


static func _script_path(class_id: String) -> String:
	match class_id:
		RS_CLASS:
			return "res://addons/netfox/rollback/rollback-synchronizer.gd"
		TI_CLASS:
			return "res://addons/netfox/tick-interpolator.gd"
		PS_CLASS:
			return "res://addons/netfox/rollback/predictive-synchronizer.gd"
		_:
			return ""


static func _strip_multiplayer_synchronizer(root: Node) -> void:
	var sync := root.get_node_or_null("MultiplayerSynchronizer")
	if sync != null:
		sync.queue_free()


static func _clock_tick() -> int:
	var nt := _autoload("NetworkTime")
	if nt == null:
		return -1
	return int(nt.get("tick"))


static func _history_server() -> Node:
	return _autoload("NetworkHistoryServer")


static func _autoload(node_name: String) -> Node:
	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return null
	return (tree as SceneTree).root.get_node_or_null(node_name)
