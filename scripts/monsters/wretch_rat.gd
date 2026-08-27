class_name WretchRat
extends "res://scripts/monsters/summon.gd"

## Queen's Rat Summon: small sphere minion for the Rat Queen. Sight-only aggro;
## explodes on player touch while chasing. Dies with host / fireball.

const GameWorldScript := preload("res://scripts/game_world.gd")

const SPHERE_MESH_RADIUS := 0.12
const FLASH_SPHERE_ALPHA := 0.6
const CHARGE_PULSE_HZ := 8.0
const LIGHT_START_RANGE := 0.15
## Queen's Rat Summon minions roam farther and hug the outer leash ring.
const LEASH_RADIUS_MULT := 1.4
const RAT_PATROL_EDGE_MIN := 0.88
const RAT_PATROL_EDGE_MAX := 0.99
## Calm patrol: long pauses, slow walks across the leash.
const RAT_IDLE_DURATION_SEC := 0.7
const RAT_PATROL_SPEED_MULT := 0.5
## Host alert: tiny idle pauses so rats keep scurrying toward the sound.
const AGITATED_IDLE_SEC := 0.08
const AGITATED_SPEED_MULT := 1.25
const AGITATED_SOUND_BLEND := 0.72
const AGITATED_LATERAL_JITTER := 0.4
## After Command Pack orb lands: arrive, then scout around the site.
const INVESTIGATE_ARRIVE_DIST := 0.85
const EXPLORE_RADIUS_MIN := 1.4
const EXPLORE_RADIUS_MAX := 3.8
const EXPLORE_ANGLE_STEP := 1.85

@export_range(0.2, 2.0, 0.05) var explode_radius: float = 0.55
## Knockback reaches farther than the damage / visual burst radius.
@export_range(0.5, 4.0, 0.05) var knockback_radius: float = 1.75
@export_range(0.1, 2.0, 0.01) var charge_sec: float = 0.34
@export_range(0.05, 0.5, 0.01) var flash_sec: float = 0.09
@export var glow_color: Color = Color(0.25, 1.0, 0.35, 1.0)
@export_range(1.0, 20.0, 0.5) var charge_light_energy: float = 12.0
@export_range(0.0, 40.0, 0.5) var explode_monster_damage: float = 8.0

var _exploding: bool = false
var _exploded: bool = false
var _charge_age: float = 0.0
var _host_alert: bool = false
var _alert_sound_goal: Vector3 = Vector3.ZERO
var _has_alert_sound: bool = false
var _calm_move_speed: float = 4.4
var _investigate_center: Vector3 = Vector3.ZERO
var _exploring_landing: bool = false
var _explore_angle: float = 0.0

@onready var _explode_light: OmniLight3D = $Body/ExplodeLight


func bind_to_host(p_host: Node, p_leash_radius: float = 10.0) -> void:
	super.bind_to_host(p_host, p_leash_radius * LEASH_RADIUS_MULT)
	idle_duration_sec = RAT_IDLE_DURATION_SEC
	_calm_move_speed = move_speed


func sync_from_host_state(state: int) -> void:
	super.sync_from_host_state(state)
	_host_alert = state == MonsterAIScript.State.ALERT
	if _host_alert:
		_apply_agitation(true)
		if (
			_ai_state == MonsterAIScript.State.IDLE
			or _ai_state == MonsterAIScript.State.ALERT
		):
			_begin_patrol()
		return
	_apply_agitation(false)
	clear_host_alert_sound()


func begin_recall() -> void:
	## Drop investigate / alert scramble and run all the way to the Rat Queen.
	_exploring_landing = false
	_host_alert = false
	_apply_agitation(false)
	clear_host_alert_sound()
	super.begin_recall()


func _on_recall_finished() -> void:
	## Spread on the leash edge and resume searching with eyes off.
	_set_chase_eyes_active(false)
	_begin_patrol()


func set_host_alert_sound(world_position: Vector3) -> void:
	_alert_sound_goal = world_position
	_has_alert_sound = true
	if not _host_alert:
		return
	if (
		_ai_state == MonsterAIScript.State.IDLE
		or _ai_state == MonsterAIScript.State.ALERT
	):
		_begin_patrol()


func clear_host_alert_sound() -> void:
	_has_alert_sound = false


func set_forced_investigate(world_position: Vector3, free_leash: bool = true) -> void:
	set_forced_investigate_explore(world_position, free_leash, _rng.randf() * TAU)


func set_forced_investigate_explore(
	world_position: Vector3, free_leash: bool = true, sector_rad: float = 0.0
) -> void:
	super.set_forced_investigate(world_position, free_leash)
	_investigate_center = world_position
	_exploring_landing = false
	_explore_angle = sector_rad


func clear_forced_hunt() -> void:
	super.clear_forced_hunt()
	_exploring_landing = false


func _tick_patrol(_delta: float) -> void:
	## Calm search is half speed; chase / recall / investigate keep full speed.
	if not _host_alert:
		var saved := move_speed
		move_speed = _calm_move_speed * RAT_PATROL_SPEED_MULT
		super._tick_patrol(_delta)
		move_speed = saved
		return
	super._tick_patrol(_delta)


func _tick_chase(_delta: float) -> void:
	if aggro_mode == AggroMode.COMMAND_INVESTIGATE:
		_tick_investigate_explore()
	super._tick_chase(_delta)


func _tick_investigate_explore() -> void:
	## Run to the orb land point, then keep scouting around it in rotating directions.
	if not has_forced_hunt_goal and not _exploring_landing:
		return
	if not _exploring_landing:
		var to_land := Vector3(
			forced_hunt_goal.x - global_position.x,
			0.0,
			forced_hunt_goal.z - global_position.z
		)
		if to_land.length() > INVESTIGATE_ARRIVE_DIST:
			return
		_investigate_center = forced_hunt_goal
		_exploring_landing = true
		_pick_explore_waypoint()
		return
	var to_waypoint := Vector3(
		forced_hunt_goal.x - global_position.x,
		0.0,
		forced_hunt_goal.z - global_position.z
	)
	if to_waypoint.length() <= INVESTIGATE_ARRIVE_DIST:
		_pick_explore_waypoint()


func _pick_explore_waypoint() -> void:
	## Advance angle so each hop covers a different direction around the land site.
	_explore_angle += EXPLORE_ANGLE_STEP + _rng.randf_range(-0.45, 0.55)
	var dist := _rng.randf_range(EXPLORE_RADIUS_MIN, EXPLORE_RADIUS_MAX)
	forced_hunt_goal = Vector3(
		_investigate_center.x + cos(_explore_angle) * dist,
		global_position.y,
		_investigate_center.z + sin(_explore_angle) * dist
	)
	has_forced_hunt_goal = true
	aggro_mode = AggroMode.COMMAND_INVESTIGATE


func _apply_agitation(agitated: bool) -> void:
	if agitated:
		idle_duration_sec = AGITATED_IDLE_SEC
		move_speed = _calm_move_speed * AGITATED_SPEED_MULT
	else:
		idle_duration_sec = RAT_IDLE_DURATION_SEC
		move_speed = _calm_move_speed


func _random_leash_edge_point() -> Vector3:
	if _host_alert and _has_alert_sound:
		return _agitated_point_toward_sound()
	var host_pos := _host_position()
	## Prefer the far side of the ring so each walk crosses more ground.
	var from_host := Vector3(
		global_position.x - host_pos.x,
		0.0,
		global_position.z - host_pos.z
	)
	var angle: float
	if from_host.length_squared() > 0.05:
		angle = atan2(from_host.z, from_host.x) + PI
		angle += _rng.randf_range(-1.0, 1.0)
	else:
		angle = _rng.randf() * TAU
	var dist := leash_radius * _rng.randf_range(RAT_PATROL_EDGE_MIN, RAT_PATROL_EDGE_MAX)
	return Vector3(
		host_pos.x + cos(angle) * dist,
		global_position.y,
		host_pos.z + sin(angle) * dist
	)


func _agitated_point_toward_sound() -> Vector3:
	## Bias leash-edge scurry toward the host's heard point, with lateral jitter.
	var host_pos := _host_position()
	var to_sound := Vector3(
		_alert_sound_goal.x - host_pos.x,
		0.0,
		_alert_sound_goal.z - host_pos.z
	)
	var angle := _rng.randf() * TAU
	var dir := Vector3(cos(angle), 0.0, sin(angle))
	if to_sound.length_squared() > 0.0001:
		var toward := to_sound.normalized()
		var lateral := Vector3(-toward.z, 0.0, toward.x)
		var side := _rng.randf_range(-AGITATED_LATERAL_JITTER, AGITATED_LATERAL_JITTER)
		dir = (toward * AGITATED_SOUND_BLEND + lateral * side).normalized()
	var dist := leash_radius * _rng.randf_range(0.55, RAT_PATROL_EDGE_MAX)
	return Vector3(
		host_pos.x + dir.x * dist,
		global_position.y,
		host_pos.z + dir.z * dist
	)


func _tick_alert(_delta: float) -> void:
	## Agitated rats don't freeze — keep scurrying on alert.
	if _host_alert:
		if _should_enforce_leash() and _try_pull_to_leash():
			return
		_begin_patrol()
		return
	super._tick_alert(_delta)


func apply_knockback(dir: Vector3, _impulse: Vector3 = Vector3.ZERO) -> void:
	## Any knock contact kills the rat.
	if not is_alive() or _exploding or _exploded:
		return
	if dir.length_squared() > 0.0001:
		_last_hit_dir = dir.normalized()
	kill()


func _physics_process(delta: float) -> void:
	if _exploded:
		return
	if _exploding:
		_tick_explode_charge(delta)
		return
	super._physics_process(delta)


func _try_touch_damage(target: Node3D) -> void:
	## Single power: explode on player contact while chasing.
	if _exploding or _exploded or not is_alive():
		return
	if _ai_state != MonsterAIScript.State.CHASE:
		return
	if not _is_player_target(target) and not _player_in_attack_range():
		return
	_begin_explode()


func _is_player_target(target: Node3D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target.is_in_group("player"):
		return true
	return (
		target.has_method("apply_rat_explode_hit")
		or target.has_method("apply_wretch_command_hit")
	)


func _player_in_attack_range() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	for node in tree.get_nodes_in_group("player"):
		if node == null or not is_instance_valid(node) or not (node is Node3D):
			continue
		var player := node as Node3D
		var flat := Vector3(
			player.global_position.x - global_position.x,
			0.0,
			player.global_position.z - global_position.z
		)
		if flat.length() <= attack_range:
			return true
	return false


func _begin_explode() -> void:
	if _exploding or _exploded:
		return
	_exploding = true
	_charge_age = 0.0
	_cancel_cast()
	velocity = Vector3.ZERO

	var light := _explode_light
	if light != null:
		light.light_color = glow_color
		light.light_energy = charge_light_energy * 0.35
		light.omni_range = LIGHT_START_RANGE


func _tick_explode_charge(delta: float) -> void:
	if Engine.is_editor_hint() or not is_alive():
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	_apply_knockback_bleed(delta)
	move_and_slide()

	_charge_age += delta
	var t := clampf(_charge_age / maxf(charge_sec, 0.05), 0.0, 1.0)
	var light := _explode_light
	if light != null and is_instance_valid(light):
		## Strength pulses up/down while range grows toward explode_radius.
		var pulse := 0.35 + 0.65 * absf(sin(_charge_age * CHARGE_PULSE_HZ * TAU))
		var peak := lerpf(charge_light_energy * 0.45, charge_light_energy, t)
		light.light_energy = peak * pulse
		light.omni_range = lerpf(LIGHT_START_RANGE, explode_radius, t)

	if _charge_age >= charge_sec:
		_detonate()


func _detonate() -> void:
	if _exploded:
		return
	_exploded = true
	_exploding = true

	var origin := global_position + Vector3(0.0, 0.12, 0.0)
	## Hide / free authored visuals first so the burst reads clearly.
	_free_visual_children()
	_spawn_explode_flash(origin)
	_apply_explode_hits(origin)
	call_deferred("queue_free")


func _free_visual_children() -> void:
	for child_name in ["Body", "Head", "CollisionShape3D"]:
		var child := get_node_or_null(child_name)
		if child != null and is_instance_valid(child):
			child.queue_free()
	_explode_light = null


func _apply_explode_hits(origin: Vector3) -> void:
	var tree := get_tree()
	if tree == null:
		return

	var push_radius := maxf(knockback_radius, explode_radius)
	for node in tree.get_nodes_in_group("player"):
		if node == null or not is_instance_valid(node) or not (node is Node3D):
			continue
		var player := node as Node3D
		var flat := Vector3(
			player.global_position.x - origin.x,
			0.0,
			player.global_position.z - origin.z
		)
		if flat.length() > push_radius:
			continue
		if player.has_method("apply_speed_boost"):
			player.call("apply_speed_boost", 0.75, 0.25)

	if explode_monster_damage <= 0.0:
		return
	for node in tree.get_nodes_in_group("combat_target"):
		if node == null or not is_instance_valid(node) or node == self:
			continue
		if not (node is Node3D):
			continue
		var victim := node as Node3D
		if origin.distance_to(victim.global_position) > explode_radius:
			continue
		Character.apply_hit(victim, explode_monster_damage, self)


func _spawn_explode_flash(origin: Vector3) -> void:
	## Prefer the rat's 3D parent so the burst stays in the match world.
	var parent: Node = get_parent()
	if parent == null:
		parent = GameWorldScript.find_match_root(get_tree())
	if parent == null:
		return

	var flash := Node3D.new()
	flash.name = "WretchRatExplodeFlash"
	flash.top_level = true
	parent.add_child(flash)
	flash.global_position = origin

	var sphere := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = SPHERE_MESH_RADIUS
	mesh.height = SPHERE_MESH_RADIUS * 2.0
	sphere.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(glow_color.r, glow_color.g, glow_color.b, FLASH_SPHERE_ALPHA)
	mat.emission_enabled = true
	mat.emission = glow_color
	mat.emission_energy_multiplier = 6.0
	sphere.material_override = mat
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sphere.layers = WorldVisualLayers.WORLD
	sphere.scale = Vector3.ONE * 0.2
	flash.add_child(sphere)

	var light := OmniLight3D.new()
	light.light_color = glow_color
	light.light_energy = charge_light_energy
	light.omni_range = explode_radius * 0.5
	light.shadow_enabled = false
	light.light_cull_mask = WorldVisualLayers.SCENE_LIGHT_MASK
	flash.add_child(light)

	var target_scale := explode_radius / SPHERE_MESH_RADIUS
	var duration := maxf(flash_sec, 0.05)
	var tween := flash.create_tween()
	tween.set_parallel(true)
	tween.tween_property(sphere, "scale", Vector3.ONE * target_scale, duration)\
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(light, "omni_range", explode_radius * 1.5, duration)\
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(light, "light_energy", 0.0, duration)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(mat, "albedo_color:a", 0.0, duration)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(flash.queue_free)
