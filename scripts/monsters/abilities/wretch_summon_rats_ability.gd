@tool
class_name WretchSummonRatsAbility
extends "res://scripts/monsters/monster_ability.gd"

## Right-hand ambient summon: slow green orb drops to the ground, then a rat appears.

const WretchRatScene := preload("res://scenes/monsters/evaluating/wretch_rat.tscn")
const WretchSummonDropOrbScript := preload(
	"res://scripts/monsters/abilities/wretch_summon_drop_orb.gd"
)
const GameWorldScript := preload("res://scripts/game_world.gd")

@export var spawn_forward_m: float = 0.9
@export var spawn_side_jitter_m: float = 0.45
@export var chase_cooldown_sec: float = 8.0
@export_range(0.4, 3.0, 0.05) var drop_duration_sec: float = 1.1


func _ready() -> void:
	hand_side = HandSide.RIGHT
	requires_target = false
	requires_chase_target = false
	min_cast_range = 0.0
	max_cast_range = 0.0
	if ability_id.is_empty():
		ability_id = "summon_rats"
	if display_name == "Ability":
		display_name = "Summon Rats"
	telegraph_color = Color(0.3, 0.95, 0.4, 1.0)
	cooldown_sec = 20.0
	windup_sec = 0.55


func can_cast() -> bool:
	if not super.can_cast():
		return false
	var host := _resolve_summon_host(_find_monster())
	return host != null and bool(host.call("can_spawn"))


func begin_cooldown() -> void:
	var monster := _find_monster()
	## Alert: no long cooldown — only wait out the drop animation before the next cast.
	if (
		monster != null
		and monster.has_method("is_ai_alert")
		and bool(monster.call("is_ai_alert"))
	):
		_cooldown_left = maxf(0.0, drop_duration_sec)
		return
	var cd := cooldown_sec
	if monster != null and monster.has_method("get_summon_cooldown_sec"):
		cd = float(monster.call("get_summon_cooldown_sec"))
	elif monster != null and monster.has_method("is_ai_chasing") and bool(
		monster.call("is_ai_chasing")
	):
		cd = chase_cooldown_sec
	_cooldown_left = maxf(0.0, cd)


func _fire_cast(monster: Monster, _target: Node3D) -> void:
	if monster == null:
		return
	var host := _resolve_summon_host(monster)
	if host == null or not bool(host.call("can_spawn")):
		return
	var parent := _spawn_parent(monster)
	if parent == null:
		return
	if host.has_method("begin_pending_spawn"):
		host.call("begin_pending_spawn")
	var land := _spawn_position(monster)
	var origin := resolve_cast_origin(monster)
	var orb = WretchSummonDropOrbScript.spawn(parent, origin, land, drop_duration_sec)
	var pending_open := [true]
	var release_pending := func() -> void:
		if not pending_open[0]:
			return
		pending_open[0] = false
		if host != null and is_instance_valid(host) and host.has_method("complete_pending_spawn"):
			host.call("complete_pending_spawn")
	orb.landed.connect(
		func(world_pos: Vector3) -> void:
			_spawn_rat_at(monster, host, parent, world_pos)
			release_pending.call()
	)
	orb.tree_exiting.connect(release_pending)


func _spawn_rat_at(monster: Monster, host: Node, parent: Node, world_pos: Vector3) -> void:
	if monster == null or not is_instance_valid(monster):
		return
	if host == null or not is_instance_valid(host):
		return
	if parent == null or not is_instance_valid(parent):
		return
	var max_n := int(host.get("max_summons")) if "max_summons" in host else 3
	var count := int(host.call("summon_count")) if host.has_method("summon_count") else 0
	if count >= max_n:
		return
	var rat: Node3D = WretchRatScene.instantiate() as Node3D
	if rat == null:
		return
	parent.add_child(rat)
	rat.global_position = world_pos
	var leash := 10.0
	if "default_leash_radius" in host:
		leash = float(host.get("default_leash_radius"))
	if rat.has_method("bind_to_host"):
		rat.call("bind_to_host", monster, leash)
	host.call("register_summon", rat)
	## If the host is locked onto a player, new rats join the hunt immediately.
	var locked: Node3D = null
	if monster.has_method("get_locked_player_target"):
		locked = monster.call("get_locked_player_target") as Node3D
	if locked != null and is_instance_valid(locked) and rat.has_method("set_forced_hunt"):
		rat.call("set_forced_hunt", locked, true)
	## Lookdev: auto-despawn preview rats so the studio stays clean.
	if Engine.is_editor_hint() or has_meta("lookdev_preview_parent"):
		var tree := rat.get_tree()
		if tree != null:
			tree.create_timer(4.0).timeout.connect(
				func() -> void:
					if is_instance_valid(rat) and rat is Character:
						(rat as Character).kill()
					elif is_instance_valid(rat):
						rat.queue_free()
			)


func _spawn_position(monster: Monster) -> Vector3:
	var forward := -monster.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	var right := monster.global_transform.basis.x
	right.y = 0.0
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()
	var side := (randf() * 2.0 - 1.0) * spawn_side_jitter_m
	return monster.global_position + forward * spawn_forward_m + right * side + Vector3(
		0.0, 0.05, 0.0
	)


func _resolve_summon_host(monster: Monster) -> Node:
	if monster == null:
		return null
	if monster.has_method("get_summon_host"):
		return monster.call("get_summon_host") as Node
	return monster.get_node_or_null("SummonHost")


func _spawn_parent(monster: Monster) -> Node:
	if has_meta("lookdev_preview_parent"):
		var preview_parent = get_meta("lookdev_preview_parent")
		if preview_parent is Node and is_instance_valid(preview_parent):
			return preview_parent as Node
	var tree := monster.get_tree() if monster != null else get_tree()
	if tree != null:
		var match_root := GameWorldScript.find_match_root(tree)
		if match_root != null:
			return match_root
		if tree.current_scene != null:
			return tree.current_scene
	return monster.get_parent() if monster != null else self
