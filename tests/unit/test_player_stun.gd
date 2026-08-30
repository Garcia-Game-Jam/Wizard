class_name TestPlayerStun
extends RefCounted

## Slice 1: stun from hit payload, no RPC, no visual_active net path.

const PlayerScene := preload("res://scenes/characters/player.tscn")


func run(tree: SceneTree) -> int:
	var failures := 0
	failures += _test_hit_stuns(tree)
	failures += _test_net_paths()
	return failures


func _test_hit_stuns(tree: SceneTree) -> int:
	var holder := Node3D.new()
	tree.root.add_child(holder)
	var player := PlayerScene.instantiate() as Character
	holder.add_child(player)
	var stun := player.get_node_or_null("Stun")
	if stun == null:
		holder.queue_free()
		push_error("Player must author Stun")
		return 1
	if stun.has_method("rpc_begin_charger_hit"):
		holder.queue_free()
		push_error("Stun must not expose rpc_begin_charger_hit")
		return 1
	var launch := Vector3(4.0, 8.0, 0.0)
	var payload := CombatPayload.new()
	payload.effects.append(Stun.with(launch))
	player.apply(player, payload)
	var err := ""
	if not bool(stun.call("is_stunned")):
		err = "Stun payload must set _stunned"
	elif not player.velocity.is_equal_approx(launch):
		err = "Stun begin must apply launch velocity"
	holder.queue_free()
	if err.is_empty():
		return 0
	push_error(err)
	return 1


func _test_net_paths() -> int:
	var player := Player.new()
	var paths := player.net_state_paths()
	player.free()
	if paths.has("Stun:visual_active"):
		push_error("Stun:visual_active must not be net state")
		return 1
	if not paths.has("Stun:_stunned"):
		push_error("Stun:_stunned must remain net state")
		return 1
	return 0
