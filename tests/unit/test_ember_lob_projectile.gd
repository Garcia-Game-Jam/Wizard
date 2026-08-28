class_name TestEmberLobProjectile
extends RefCounted

## Ember lobs must spend HP on a nearby pawn even when Area3D never overlaps
## (rollback tick path + dive detonating at the character root). They must not
## shove the pawn — ember abilities have no knockback.

const PlayerScene := preload("res://scenes/characters/player.tscn")
const EmberLobScene := preload("res://scenes/monsters/abilities/ember_lob_projectile.tscn")


func run(tree: SceneTree) -> int:
	var failures := 0
	failures += _test_impact_damages_nearby_player_without_knockback(tree)
	return failures


func _holder(tree: SceneTree) -> Node3D:
	var holder := Node3D.new()
	tree.root.add_child(holder)
	return holder


func _test_impact_damages_nearby_player_without_knockback(tree: SceneTree) -> int:
	var holder := _holder(tree)
	var player := PlayerScene.instantiate() as Character
	holder.add_child(player)
	player.global_position = Vector3(0.0, 0.0, 0.0)
	player.velocity = Vector3.ZERO
	var max_hp := player.max_health
	var lob := EmberLobScene.instantiate() as EmberLobProjectile
	holder.add_child(lob)
	lob.global_position = Vector3(0.0, 0.2, 0.4)
	lob.monitoring = true
	lob.call("_finish", true)
	var err := ""
	if is_equal_approx(player.current_health, max_hp):
		err = (
			"Expected ember lob impact near the player to spend HP; stayed at %.1f/%.1f"
			% [player.current_health, max_hp]
		)
	elif player.velocity.length_squared() > 0.01:
		err = "Ember lob must not knock the player back (velocity %s)" % player.velocity
	holder.queue_free()
	if err.is_empty():
		return 0
	push_error(err)
	return 1
