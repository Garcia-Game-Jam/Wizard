class_name MonsterSpellHit
extends RefCounted

## Shared overlap rules for monster projectiles: walls, players, NPCs, wards.

enum Kind { IGNORE, WARD, COMBAT, WALL }

const SpellWardBlockScript := preload("res://scripts/spells/spell_ward_block.gd")

const COLLISION_MASK := 1 | 2


static func apply_mask(obj: CollisionObject3D) -> void:
	if obj == null:
		return
	obj.collision_layer = 0
	obj.collision_mask = COLLISION_MASK


static func kind(body: Node, caster: Variant = null) -> Kind:
	if body == null or not is_instance_valid(body):
		return Kind.IGNORE
	var caster_node := SpellWardBlockScript.live_node(caster)
	if _is_caster(body, caster_node):
		return Kind.IGNORE
	var ward := SpellWardBlockScript.ward_from_node(body)
	if ward != null:
		if caster_node != null and ward.has_method("is_owned_by"):
			if bool(ward.call("is_owned_by", caster_node)):
				return Kind.IGNORE
		return Kind.WARD
	if is_combat_body(body):
		return Kind.COMBAT
	if is_wall(body):
		return Kind.WALL
	return Kind.IGNORE


static func is_combat_body(body: Node) -> bool:
	if body == null:
		return false
	if not Character.is_node_alive(body):
		return false
	return (
		body.is_in_group("player")
		or body.is_in_group("monster")
		or body.is_in_group("combat_target")
	)


static func is_wall(body: Node) -> bool:
	if body == null:
		return false
	if not (body is StaticBody3D):
		return false
	var name := str(body.name).to_lower()
	return not (name == "floor" or name.begins_with("floor"))


static func _is_caster(body: Node, caster: Node) -> bool:
	return caster != null and body == caster
