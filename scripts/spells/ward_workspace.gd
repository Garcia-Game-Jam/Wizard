@tool
extends Node3D

## Ward studio. No default dome — Inspector buttons play the lifecycle.

const WardShieldScript := preload("res://scripts/spells/ward_shield.gd")
const FireballProjectileScript := preload("res://scripts/spells/fireball_projectile.gd")
const WardSpell := preload("res://scenes/spells/ward/ward.tres")
const FireballSpell := preload("res://scenes/spells/fireball/fireball.tres")

@export_group("Preview")
## Extra push along the wand aim before spawn (0 = tip).
@export_range(0.0, 1.5, 0.05, "or_greater") var tip_forward_nudge: float = 0.0
@export_tool_button("Cast Ward", "Callable")
var cast_ward_action := cast_ward_preview
@export_tool_button("Hold Ward", "Callable")
var hold_ward_action := hold_ward_preview
@export_tool_button("Fireball", "Callable")
var fireball_action := fireball_preview
@export_tool_button("Release Ward", "Callable")
var release_ward_action := release_ward_preview

var _preview_ward: Node3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_cast_bucket()
	_force_wand_tip_visible(_wand())
	_force_wand_tip_visible(_attack_wand())
	_aim_attack_wand()


func _force_wand_tip_visible(wand: Node3D) -> void:
	if wand == null:
		return
	var tip := wand.get_node_or_null("Model/Tip") as Node3D
	if tip == null:
		tip = wand.get_node_or_null("Tip") as Node3D
	if tip != null:
		tip.visible = true


func cast_ward_preview() -> void:
	if not is_inside_tree():
		return
	_clear_wards()
	var pose := _wand_pose(_wand())
	_play_wand_cast(_wand())
	var bucket := _ensure_cast_bucket()
	_preview_ward = WardShieldScript.spawn(bucket, pose["origin"], pose["direction"]) as Node3D
	_apply_authored_combat(_preview_ward)
	_bind_preview_ward()
	_aim_attack_wand()


func hold_ward_preview() -> void:
	if not is_inside_tree():
		return
	_clear_wards()
	var wand := _wand()
	var pose := _wand_pose(wand)
	_play_wand_cast(wand)
	var packed: PackedScene = load("res://scenes/spells/ward/ward.tscn") as PackedScene
	if packed == null:
		return
	var ward := packed.instantiate() as Node3D
	var bucket := _ensure_cast_bucket()
	bucket.add_child(ward)
	ward.process_mode = Node.PROCESS_MODE_ALWAYS
	if ward.has_method("set_caster"):
		ward.call("set_caster", wand)
	_apply_authored_combat(ward)
	if ward.has_method("start_wand_follow"):
		ward.call("start_wand_follow", pose["origin"], pose["direction"], 1, wand)
	_preview_ward = ward
	_bind_preview_ward()
	_aim_attack_wand()


func fireball_preview() -> void:
	if not is_inside_tree():
		return
	_clear_fireballs()
	_aim_attack_wand()
	var attacker := _attack_wand()
	var pose := _wand_pose(attacker if attacker != null else _wand())
	var target := _ward_aim_point()
	var origin: Vector3 = pose["origin"]
	var direction := target - origin
	if direction.length_squared() < 0.0001:
		direction = pose["direction"]
	else:
		direction = direction.normalized()
	_play_wand_cast(attacker, FireballSpell)
	var ball: Node = FireballProjectileScript.spawn(
		_ensure_cast_bucket(), origin, direction, null, true, 1.0
	)
	if ball is Node:
		(ball as Node).process_mode = Node.PROCESS_MODE_ALWAYS


func release_ward_preview() -> void:
	if _preview_ward == null or not is_instance_valid(_preview_ward):
		return
	if _preview_ward.has_method("plant"):
		_preview_ward.call("plant")
	_aim_attack_wand()


func _bind_preview_ward() -> void:
	if _preview_ward == null:
		return
	_preview_ward.process_mode = Node.PROCESS_MODE_ALWAYS
	if not _preview_ward.tree_exited.is_connected(_on_preview_exited):
		_preview_ward.tree_exited.connect(_on_preview_exited, CONNECT_ONE_SHOT)


func _on_preview_exited() -> void:
	_preview_ward = null


func _apply_authored_combat(ward: Node) -> void:
	if ward == null or WardSpell == null:
		return
	var max_hp := float(WardSpell.get("max_health"))
	if max_hp > 0.0:
		ward.set("block_hp", max_hp)
		if ward.has_method("set_hit_points"):
			ward.call("set_hit_points", max_hp)
	ward.set("regen_delay_sec", float(WardSpell.get("regen_delay_sec")))
	ward.set("regen_per_sec", float(WardSpell.get("regen_per_sec")))


func _wand() -> Node3D:
	return get_node_or_null("Wand") as Node3D


func _attack_wand() -> Node3D:
	return get_node_or_null("AttackWand") as Node3D


func _ward_aim_point() -> Vector3:
	if _preview_ward != null and is_instance_valid(_preview_ward):
		return _preview_ward.global_position
	var pose := _wand_pose(_wand())
	return pose["origin"] + pose["direction"] * 1.4


func _aim_attack_wand() -> void:
	var attacker := _attack_wand()
	var ward_wand := _wand()
	if attacker == null or ward_wand == null:
		return
	var target := _resolve_cast_origin(ward_wand)
	if attacker.global_position.distance_squared_to(target) < 0.0001:
		return
	attacker.look_at(target, Vector3.UP)
	_force_wand_tip_visible(attacker)


func _wand_pose(wand: Node3D) -> Dictionary:
	var origin := Vector3(0.15, 1.05, 1.15)
	var direction := Vector3(0.0, 0.0, -1.0)
	if wand != null:
		origin = _resolve_cast_origin(wand)
		direction = -wand.global_transform.basis.z
	if direction.length_squared() < 0.0001:
		direction = Vector3(0.0, 0.0, -1.0)
	else:
		direction = direction.normalized()
	origin += direction * tip_forward_nudge
	return {"origin": origin, "direction": direction}


func _play_wand_cast(wand: Node3D, spell: Resource = WardSpell) -> void:
	if wand != null and wand.has_method("play_cast_success"):
		wand.call("play_cast_success", spell, true)


func _resolve_cast_origin(wand: Node3D) -> Vector3:
	var tip := wand.get_node_or_null("Model/CastOrigin") as Node3D
	if tip == null:
		tip = wand.get_node_or_null("CastOrigin") as Node3D
	if tip != null:
		return tip.global_position
	if wand.has_method("get_cast_origin"):
		return wand.call("get_cast_origin") as Vector3
	return wand.global_position


func _ensure_cast_bucket() -> Node3D:
	var bucket := get_node_or_null("CastPreview") as Node3D
	if bucket != null:
		bucket.process_mode = Node.PROCESS_MODE_ALWAYS
		return bucket
	bucket = Node3D.new()
	bucket.name = "CastPreview"
	bucket.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(bucket)
	if Engine.is_editor_hint():
		var root := get_tree().edited_scene_root
		if root != null:
			bucket.owner = root
	return bucket


func _clear_wards() -> void:
	if _preview_ward != null and is_instance_valid(_preview_ward):
		_free_preview_child(_preview_ward)
	_preview_ward = null
	var bucket := get_node_or_null("CastPreview")
	if bucket == null:
		return
	for child in bucket.get_children():
		if child is FireballProjectile:
			continue
		_free_preview_child(child)


func _clear_fireballs() -> void:
	var bucket := get_node_or_null("CastPreview")
	if bucket == null:
		return
	for child in bucket.get_children():
		if child is FireballProjectile:
			_free_preview_child(child)


func _free_preview_child(child: Node) -> void:
	if Engine.is_editor_hint():
		child.free()
	else:
		child.queue_free()
