class_name WardSlotChannel
extends RefCounted

## Player-slot ward: dome rides the camera; a cylinder runs from the wand tip.

const SpellEphemeralFxScript := preload("res://scripts/spells/spell_ephemeral_fx.gd")
const WardSpell := preload("res://scenes/spells/ward/ward.tres")

var _ward: Node


func consume() -> Node:
	var ward := _ward
	_ward = null
	if ward != null and is_instance_valid(ward):
		return ward
	return null


func begin(player: Node3D) -> void:
	drop()
	if player == null:
		return
	var host := _follow_host(player)
	var parent: Node = host
	if parent == null:
		parent = SpellEphemeralFxScript.resolve_parent(player)
	if parent == null:
		return
	var packed: PackedScene = load(SpellDefinition.world_scene_path("ward")) as PackedScene
	if packed == null:
		return
	var origin := Vector3.ZERO
	var direction := Vector3(0.0, 0.0, -1.0)
	if player.has_method("get_view_origin"):
		origin = player.call("get_view_origin") as Vector3
	if player.has_method("get_view_direction"):
		direction = player.call("get_view_direction") as Vector3
	var ward: Node = packed.instantiate()
	if ward is Node3D:
		SpellEphemeralFxScript.add_child_at(parent, ward as Node3D, origin)
	else:
		parent.add_child(ward)
	if ward.has_method("set_caster"):
		ward.call("set_caster", player)
	_apply_authored_combat(ward, player)
	if ward.has_method("start_wand_follow"):
		ward.call("start_wand_follow", origin, direction, 1, host)
	_ward = ward


func plant() -> void:
	if _ward == null or not is_instance_valid(_ward):
		_ward = null
		return
	if _ward.has_method("plant"):
		_ward.call("plant")


func drop() -> void:
	if _ward == null:
		return
	var ward := _ward
	_ward = null
	if not is_instance_valid(ward):
		return
	var following := (
		bool(ward.call("is_channel_following"))
		if ward.has_method("is_channel_following")
		else true
	)
	if not following:
		return
	if ward.has_method("shatter"):
		ward.call("shatter")
	else:
		ward.queue_free()


func _apply_authored_combat(ward: Node, player: Node3D) -> void:
	if player != null and player.has_method("get_spell_loadout"):
		var loadout: Node = player.call("get_spell_loadout") as Node
		if loadout != null and loadout.has_method("get_ward_runtime"):
			var runtime: Resource = loadout.call("get_ward_runtime") as Resource
			if runtime != null and ward.has_method("bind_runtime"):
				ward.call("bind_runtime", runtime)
				return
	if WardSpell == null:
		return
	var max_hp := float(WardSpell.get("max_health"))
	if max_hp > 0.0:
		ward.set("block_hp", max_hp)
		if ward.has_method("set_hit_points"):
			ward.call("set_hit_points", max_hp)
	ward.set("regen_delay_sec", float(WardSpell.get("regen_delay_sec")))
	ward.set("regen_per_sec", float(WardSpell.get("regen_per_sec")))


func _follow_host(player: Node3D) -> Node3D:
	if player.has_method("get_view_camera"):
		var cam: Camera3D = player.call("get_view_camera") as Camera3D
		if cam != null:
			return cam
	if "camera_pivot" in player:
		return player.get("camera_pivot") as Node3D
	return null
