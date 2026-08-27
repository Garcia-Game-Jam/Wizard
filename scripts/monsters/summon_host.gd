class_name SummonHost
extends Node

## Tracks host-linked summons. Scene-tree entrypoint under a Monster (or future player).

signal summons_changed

@export var max_summons: int = 3
@export var default_leash_radius: float = 10.0

var _summons: Array[Node] = []
var _pending_spawns: int = 0


func can_spawn() -> bool:
	_prune()
	return (_summons.size() + _pending_spawns) < max_summons


func summon_count() -> int:
	_prune()
	return _summons.size()


func begin_pending_spawn() -> void:
	_pending_spawns += 1


func complete_pending_spawn() -> void:
	_pending_spawns = maxi(0, _pending_spawns - 1)


func register_summon(summon: Node) -> void:
	if summon == null:
		return
	_prune()
	if _summons.has(summon):
		return
	_summons.append(summon)
	if not summon.tree_exiting.is_connected(_on_summon_exiting):
		summon.tree_exiting.connect(_on_summon_exiting.bind(summon))
	summons_changed.emit()


func unregister_summon(summon: Node) -> void:
	if summon == null:
		return
	_summons.erase(summon)
	summons_changed.emit()


func kill_all() -> void:
	_prune()
	var snapshot := _summons.duplicate()
	_summons.clear()
	for summon in snapshot:
		if summon == null or not is_instance_valid(summon):
			continue
		if summon is Character:
			(summon as Character).kill()
		elif summon.is_inside_tree():
			summon.queue_free()
	summons_changed.emit()


func command_attack(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		return
	_prune()
	for summon in _summons:
		if summon == null or not is_instance_valid(summon):
			continue
		if summon.has_method("set_forced_hunt"):
			summon.call("set_forced_hunt", target, true)


func command_investigate(world_position: Vector3) -> void:
	_prune()
	var count := maxi(_summons.size(), 1)
	var i := 0
	for summon in _summons:
		if summon == null or not is_instance_valid(summon):
			continue
		## Spread rats into different explore sectors around the land point.
		var sector := TAU * float(i) / float(count)
		if summon.has_method("set_forced_investigate_explore"):
			summon.call("set_forced_investigate_explore", world_position, true, sector)
		elif summon.has_method("set_forced_investigate"):
			summon.call("set_forced_investigate", world_position, true)
		i += 1


func command_recall() -> void:
	## Host calmed — pack runs home, then spreads into leashed search.
	_prune()
	for summon in _summons:
		if summon == null or not is_instance_valid(summon):
			continue
		if summon.has_method("begin_recall"):
			summon.call("begin_recall")


func sync_from_host_state(state: int) -> void:
	## Propagate packmaster AI state so summons can mirror vigilance / recall.
	_prune()
	for summon in _summons:
		if summon == null or not is_instance_valid(summon):
			continue
		if summon.has_method("sync_from_host_state"):
			summon.call("sync_from_host_state", state)


func sync_alert_sound(world_position: Vector3) -> void:
	## Soft sound cue while host is alert — rats scurry toward it (stay leashed).
	_prune()
	for summon in _summons:
		if summon == null or not is_instance_valid(summon):
			continue
		if summon.has_method("set_host_alert_sound"):
			summon.call("set_host_alert_sound", world_position)


func clear_alert_sound() -> void:
	_prune()
	for summon in _summons:
		if summon == null or not is_instance_valid(summon):
			continue
		if summon.has_method("clear_host_alert_sound"):
			summon.call("clear_host_alert_sound")


func append_relayed_interests(out: Array) -> void:
	_prune()
	for summon in _summons:
		if summon == null or not is_instance_valid(summon):
			continue
		if summon.has_method("append_relayed_interests"):
			summon.call("append_relayed_interests", out)
			continue
		if summon.has_method("get_relayed_player_interest"):
			var interest = summon.call("get_relayed_player_interest")
			if interest != null:
				out.append(interest)


func _prune() -> void:
	var kept: Array[Node] = []
	for summon in _summons:
		if summon != null and is_instance_valid(summon) and summon.is_inside_tree():
			kept.append(summon)
	_summons = kept


func _on_summon_exiting(summon: Node) -> void:
	_summons.erase(summon)
	summons_changed.emit()
