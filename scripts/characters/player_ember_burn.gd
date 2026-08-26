class_name PlayerEmberBurn
extends RefCounted

## Burn slow + DPS while standing in Ember dash trails.


static var _timers: Dictionary = {}
static var _dps: Dictionary = {}
static var _pending: Dictionary = {}


static func apply(player: Node, dps: float, slow_mult: float, refresh: float) -> void:
	if player == null:
		return
	if player.has_method("is_multiplayer_authority"):
		var tree := player.get_tree()
		var state := tree.root.get_node_or_null("GameState") if tree != null else null
		var mp := state != null and bool(state.get("is_multiplayer"))
		if mp and not player.is_multiplayer_authority():
			return
	var id := player.get_instance_id()
	_dps[id] = maxf(float(_dps.get(id, 0.0)), dps)
	_timers[id] = maxf(float(_timers.get(id, 0.0)), refresh)
	if player.has_method("apply_speed_boost"):
		player.apply_speed_boost(refresh, slow_mult)
	_pending[id] = float(_pending.get(id, 0.0)) + dps * player.get_physics_process_delta_time()


static func tick(player: Node, delta: float) -> void:
	if player == null:
		return
	var id := player.get_instance_id()
	var timer := float(_timers.get(id, 0.0))
	if timer <= 0.0:
		return
	timer -= delta
	var dps := float(_dps.get(id, 0.0))
	if dps > 0.0:
		Character.apply_hit(player, dps * delta, null)
	if timer <= 0.0:
		_timers.erase(id)
		_dps.erase(id)
		_flush_pending(id)
	else:
		_timers[id] = timer


static func _flush_pending(id: int) -> void:
	_pending[id] = 0.0
