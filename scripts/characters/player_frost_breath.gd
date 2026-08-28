class_name PlayerFrostBreath
extends RefCounted

## Frost breath slow and mana drain on armed spell.

const AshFrostBreathFlightScript := preload(
	"res://scripts/monsters/abilities/ash_frost_breath_flight.gd"
)


static func apply(player: Node, _hit_dir: Vector3) -> void:
	if not _can_apply(player):
		return
	if player.has_method("apply_speed_boost"):
		player.call(
			"apply_speed_boost",
			AshFrostBreathFlightScript.SLOW_DURATION_SEC,
			AshFrostBreathFlightScript.SLOW_MULTIPLIER
		)
	_drain_mana_if_armed(player, AshFrostBreathFlightScript.MANA_DRAIN)


static func _can_apply(player: Node) -> bool:
	if player == null:
		return false
	if not player.has_method("is_multiplayer_authority"):
		return true
	var tree := player.get_tree()
	var state := tree.root.get_node_or_null("GameState") if tree != null else null
	var mp := state != null and bool(state.get("is_multiplayer"))
	return not mp or player.is_multiplayer_authority()


static func _drain_mana_if_armed(player: Node, amount: float) -> void:
	if amount <= 0.0 or "_armed_spell" not in player:
		return
	var armed = player.get("_armed_spell")
	if armed == null:
		return
	if player.has_method("_spend_mana"):
		player.call("_spend_mana", amount)
