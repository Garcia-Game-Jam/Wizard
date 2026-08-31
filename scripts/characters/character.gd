class_name Character
extends CharacterBody3D

## 3D character shell: body/head meshes, collision, tint, and the shared HP lifecycle.
## Inherited by Player, Monster, and Summon.
## HP, slow, burn, and knock are fields on this script — set max_health per type
## scene. Hits arrive via Character.apply_hit. Subclasses vary reactions in
## _on_hurt / _on_death / _combat_groups.
## CollisionShape3D is authored per character scene — not rebuilt here.
## Appearance: mutate authored scene materials. Never allocate meshes or materials.

signal damaged(amount: float, from: Variant)
signal died(from: Variant)
signal changed(current: float, maximum: float)
signal revived

const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")
const NetClockScript := preload("res://scripts/net/net_clock.gd")
const CollisionLayersScript := preload("res://scripts/collision_layers.gd")

const DEFAULT_MAX_HEALTH := 100.0

const KNOCKBACK_TIMER_SEC := 0.35
## Extra shove after the hit, in units of _knockback_vel per second.
## 0 = impulse only. If you turn this back on, it must stay delta-scaled
## (a flat per-tick fraction turned a 9 m/s hit into 40 m/s at 60 Hz).
const KNOCKBACK_BLEED_PER_SEC := 0.0
const KNOCKBACK_DECAY := 28.0
const KNOCKBACK_HORIZONTAL := 9.0
const KNOCKBACK_UP := 3.5
const DEATH_IMPULSE_SCALE := 1.35
const DEATH_SLUMP_HORIZONTAL := 1.2
const DEATH_SLUMP_UP := 0.6
const CORPSE_GROUP := &"corpse"
const EYE_EMISSION_ENERGY := 5.5
const EYE_LIGHT_ENERGY := 2.6
## Eye glow at 0 HP: near-black, slightly tinted from authored color.
const EYE_DEAD_RGB_SCALE := Vector3(0.04, 0.06, 0.04)
const EYE_DEAD_ENERGY_SCALE := 0.28
const DEFAULT_EYE_GLOW := Color(0.2, 0.55, 1.0, 1.0)
## Pose, knockback, and HP. Subclasses append movement tells in net_state_paths().
const NET_STATE_PATHS: PackedStringArray = [
	":position",
	":velocity",
	":rotation",
	":_knockback_vel",
	":_knockback_timer",
	":_speed_boost_multiplier",
	":_speed_boost_timer",
	":_burn_dps",
	":_burn_timer",
	":current_health",
	":_eyes_chasing",
	":eye_glow_color",
]

@export_group("Appearance")
## Eye tint for scenes that author Head/Eyes. Dims toward black as HP drops.
@export var eye_glow_color: Color = DEFAULT_EYE_GLOW:
	set(value):
		if eye_glow_color.is_equal_approx(value):
			return
		eye_glow_color = value
		if is_node_ready():
			_apply_eye_glow_from_health()

@export_group("Health")
## Per-type max HP. Authored on the character scene root, not a child node.
@export_range(1.0, 1000.0, 1.0) var max_health: float = DEFAULT_MAX_HEALTH:
	set(value):
		max_health = maxf(value, 1.0)
		if current_health > max_health:
			current_health = max_health
		_emit_health_changed()

## Rewindable HP. @export_storage so netfox PropertyEntry.is_valid() (LAN).
@export_storage var current_health: float = DEFAULT_MAX_HEALTH:
	set(value):
		var next := clampf(value, 0.0, max_health)
		if is_equal_approx(current_health, next):
			return
		var was_dead := current_health <= 0.0
		current_health = next
		_emit_health_changed()
		if _host_apply_depth == 0 and not was_dead and current_health <= 0.0:
			died.emit(null)
			_on_died(null)
		if was_dead and current_health > 0.0:
			revived.emit()
			_on_revived()

@export_group("Status")
## Move multiplier while speed_boost_timer > 0. <1 slow, >1 haste.
@export var _speed_boost_multiplier: float = 1.0
@export var _speed_boost_timer: float = 0.0
@export var _burn_dps: float = 0.0
@export var _burn_timer: float = 0.0

var net_phase: int = 0
var net_telegraph: float = 0.0
## RigidBody clone while dead (player ghost + monster flop). Presentation; stage frees props.
var death_corpse: Corpse = null
var _knockback_vel: Vector3 = Vector3.ZERO
var _knockback_timer: float = 0.0
var _host_apply_depth: int = 0
var _last_hit_dir: Vector3 = Vector3.FORWARD
var _body_collision: CollisionShape3D = null
var _eyes_root: Node3D = null
var _eye_meshes: Array[MeshInstance3D] = []
var _eye_light: OmniLight3D = null
var _eyes_chasing: bool = false
var _death_physics_active := false
var _saved_floor_snap := 0.1
## Physics-frame hits (projectiles) stamp a tick; spent during that tick's
## _rollback_tick so restore does not drop HP/knock. Kept until history_start.
var _rewind_applies: Array = []

## Optional: scenes that author no Head/Body (test probes) leave these null and
## the appearance helpers below become no-ops.
@onready var head: Node3D = get_node_or_null("%Head") as Node3D
@onready var _body_mesh: MeshInstance3D = get_node_or_null("%Body") as MeshInstance3D
@onready var _head_mesh: MeshInstance3D = get_node_or_null("%HeadMesh") as MeshInstance3D


func _ready() -> void:
	collision_layer = CollisionLayersScript.CHARACTER
	collision_mask = CollisionLayersScript.CHARACTER_AND_WORLD
	current_health = max_health
	call_deferred("_bind_rewindable")


func _bind_rewindable() -> void:
	pass


func _net_rewind_profile() -> String:
	return ""


func net_state_paths() -> Array[String]:
	var paths: Array[String] = []
	for path in NET_STATE_PATHS:
		paths.append(path)
	for path in _net_state_extra():
		paths.append(path)
	return paths


func _net_state_extra() -> PackedStringArray:
	return PackedStringArray()


func is_alive() -> bool:
	return not is_dead()


func is_dead() -> bool:
	return current_health <= 0.0


func health_ratio() -> float:
	if max_health <= 0.001:
		return 1.0
	return clampf(current_health / max_health, 0.0, 1.0)


func ratio_before(amount: float) -> float:
	if max_health <= 0.001:
		return 0.0
	return clampf((current_health + maxf(amount, 0.0)) / max_health, 0.0, 1.0)


func take_damage(amount: float, from: Variant = null) -> void:
	if is_dead():
		return
	var hit := maxf(amount, 0.0)
	if hit <= 0.0:
		return
	_host_apply_depth += 1
	current_health = maxf(0.0, current_health - hit)
	_host_apply_depth -= 1
	damaged.emit(hit, from)
	_on_damaged(hit, from)
	if is_dead():
		died.emit(from)
		_on_died(from)


func kill(from: Variant = null) -> void:
	take_damage(current_health, from)


func heal(amount: float) -> void:
	if is_dead():
		return
	current_health = clampf(current_health + maxf(amount, 0.0), 0.0, max_health)


func revive() -> void:
	current_health = max_health


func _emit_health_changed() -> void:
	if not is_inside_tree():
		return
	changed.emit(current_health, max_health)
	_on_health_changed(current_health, max_health)


## The one way damage reaches a body. Group scans and physics queries hand us
## arbitrary nodes; only a Character has a pool to spend.
static func apply_hit(body: Node, amount: float, from: Variant = null) -> void:
	if not is_instance_valid(body) or not (body is Character):
		return
	var character := body as Character
	if not character.is_alive():
		return
	var tree := character.get_tree()
	var state := tree.root.get_node_or_null("GameState") if tree != null else null
	var mp := state != null and bool(state.get("is_multiplayer"))
	if mp and not character.is_multiplayer_authority():
		return
	character.take_damage(amount, from)


## Loop payload.effects. Each effect uses the existing HP / knock / stun gates.
func apply(from: Variant, payload: Resource) -> void:
	if is_dead() or payload == null or not "effects" in payload:
		return
	for effect in payload.effects:
		if effect != null and effect.has_method("apply"):
			effect.apply(self, from)


## Projectiles fly after the tick is recorded. Queue so resim can spend again.
func _apply_or_queue_rewind(from: Variant, payload: Resource) -> void:
	if (
		NetClockScript.is_ticking()
		and get_node_or_null("RollbackSynchronizer") != null
	):
		_queue_rewind_apply(from, payload, NetClockScript.tick())
		return
	apply(from, payload)


func _queue_rewind_apply(from: Variant, payload: Resource, tick: int) -> void:
	if payload == null or not _status_authority_ok():
		return
	_rewind_applies.append({
		"tick": tick,
		"from": from,
		"payload": payload.duplicate(true),
	})


func _flush_rewind_applies(tick: int) -> void:
	if _rewind_applies.is_empty():
		return
	var history_start := 0
	var tree := get_tree()
	var nr := tree.root.get_node_or_null("NetworkRollback") if tree != null else null
	if nr != null:
		history_start = int(nr.get("history_start"))
	var keep: Array = []
	for entry in _rewind_applies:
		var at := int(entry.get("tick", -1))
		if at < history_start:
			continue
		if at == tick:
			apply(entry.get("from"), entry.get("payload"))
		keep.append(entry)
	_rewind_applies = keep


func _rollback_tick(_delta: float, tick: int, _is_fresh: bool) -> void:
	_flush_rewind_applies(tick)


func combat_speed(base: float) -> float:
	return base * _speed_boost_multiplier


func apply_speed_boost(duration: float, multiplier: float) -> void:
	if not _status_authority_ok():
		return
	_speed_boost_multiplier = multiplier
	_speed_boost_timer = duration


func is_knocked() -> bool:
	return _knockback_timer > 0.0


func apply_burn(dps: float, duration_sec: float, _from: Variant = null) -> void:
	if not _status_authority_ok():
		return
	_burn_dps = maxf(_burn_dps, dps)
	_burn_timer = maxf(_burn_timer, duration_sec)


func tick_speed_boost(delta: float) -> void:
	if _speed_boost_timer <= 0.0:
		return
	_speed_boost_timer -= delta
	if _speed_boost_timer <= 0.0:
		_speed_boost_multiplier = 1.0


func tick_burn(delta: float) -> void:
	if _burn_timer <= 0.0:
		return
	if _burn_dps > 0.0:
		apply_hit(self, _burn_dps * delta, null)
	_burn_timer -= delta
	if _burn_timer <= 0.0:
		_burn_dps = 0.0


func _status_authority_ok() -> bool:
	var tree := get_tree()
	var state := tree.root.get_node_or_null("GameState") if tree != null else null
	var mp := state != null and bool(state.get("is_multiplayer"))
	if mp and not is_multiplayer_authority():
		return false
	return true


func _on_health_changed(_current: float, _maximum: float) -> void:
	_apply_eye_glow_from_health()


## Group scans hit nodes that may be freed or may not be characters at all
## (the lookdev player dummy). Only a real Character can be dead.
static func is_node_alive(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	var n := node
	while n != null:
		if n is Character:
			return (n as Character).is_alive()
		n = n.get_parent()
	return true


## Shared hit reaction: face away from the hit, dim the eyes.
func _on_damaged(amount: float, from: Variant) -> void:
	var source := _live_source(from)
	_remember_hit_dir(source)
	_apply_eye_glow_from_health()
	_on_hurt(amount, source)


## Sim death: leave combat targeting, start limp. Corpse/ghost wait for Death.commit.
func _on_died(from: Variant) -> void:
	for group in _combat_groups():
		if is_in_group(group):
			remove_from_group(group)
	var first_death := not _death_physics_active
	begin_death_physics()
	if first_death:
		_on_death(_live_source(from))


## Groups to leave on death. Monsters and summons drop out of AI targeting;
## players stay in "player" so respawn and spectating still resolve them.
func _combat_groups() -> Array[StringName]:
	return [&"combat_target"]


## Per-type hit reaction (combo triggers, hurt FX).
func _on_hurt(_amount: float, _from: Node3D) -> void:
	pass


## Per-type sim death (AI stop, ghost collision). Presentation is Death.commit.
func _on_death(_from: Node3D) -> void:
	pass


## Undo sim death after revive() or rewind restoring HP above 0. Corpse stays for the stage.
func restore_after_revive() -> void:
	var dying := _death_physics_active
	stop_death_physics()
	if not dying:
		## HP may already be full (setter no-op) while a leftover corpse remains.
		_on_stop_death_physics()
	_burn_dps = 0.0
	_burn_timer = 0.0
	_knockback_vel = Vector3.ZERO
	_knockback_timer = 0.0
	_speed_boost_timer = 0.0
	_speed_boost_multiplier = 1.0
	set_physics_process(true)
	for group in _combat_groups():
		if not is_in_group(group):
			add_to_group(group)
	_apply_eye_glow_from_health()


func _on_revived() -> void:
	restore_after_revive()


func is_death_physics() -> bool:
	return _death_physics_active


## Dead sim mode (ghost flight / AI off). Corpse flop is Corpse.spawn().
func begin_death_physics() -> void:
	if _death_physics_active:
		return
	_death_physics_active = true
	_saved_floor_snap = floor_snap_length
	floor_snap_length = 0.0
	set_physics_process(true)


func stop_death_physics() -> void:
	if not _death_physics_active:
		return
	_death_physics_active = false
	floor_snap_length = _saved_floor_snap
	velocity = Vector3.ZERO
	_on_stop_death_physics()


## Engine _physics_process. True = caller should return.
func tick_death_physics_if_active(_delta: float) -> bool:
	return _death_physics_active and not is_alive()


## Rollback tick while dead — skip living sim; ghost/corpse use their own paths.
func rollback_tick_death_if_active(_delta: float) -> bool:
	return _death_physics_active and not is_alive()


static func death_slump_velocity(hit_dir: Vector3) -> Vector3:
	var flat := Vector3(hit_dir.x, 0.0, hit_dir.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	else:
		flat = flat.normalized()
	return flat * DEATH_SLUMP_HORIZONTAL + Vector3.UP * DEATH_SLUMP_UP


static func death_tumble_spin(rad: float) -> Vector3:
	var axis := Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-0.35, 0.35),
		randf_range(-1.0, 1.0)
	)
	if axis.length_squared() < 0.0001:
		axis = Vector3.FORWARD
	return axis.normalized() * rad


func _on_stop_death_physics() -> void:
	pass


## A ward ate a spell this character cast.
func on_spell_ward_blocked(_blocked_by: Node = null) -> void:
	pass


## This character's own ward absorbed an incoming spell.
func on_own_ward_blocked(_blocked_from: Node = null) -> void:
	pass


## A hit source may already be freed by the time we react to it.
func _live_source(from: Variant) -> Node3D:
	if not is_instance_valid(from) or not (from is Node3D):
		return null
	return from as Node3D


func _remember_hit_dir(from: Node3D) -> void:
	if from == null:
		return
	var away := global_position - from.global_position
	away.y = 0.0
	if away.length_squared() > 0.0001:
		_last_hit_dir = away.normalized()


## Knock status: a shove plus a short bleed. Only stone throw and charger ram
## apply this — HP loss itself does not.
func apply_knockback(dir: Vector3, impulse: Vector3 = Vector3.ZERO) -> void:
	var tree := get_tree()
	var state := tree.root.get_node_or_null("GameState") if tree != null else null
	var mp := state != null and bool(state.get("is_multiplayer"))
	if mp and not is_multiplayer_authority():
		return
	if dir.length_squared() > 0.0001:
		_last_hit_dir = dir.normalized()
	if impulse.length_squared() < 0.0001:
		impulse = _knockback_impulse(dir)
	if is_instance_valid(death_corpse) and death_corpse.has_method("apply_hit_knock"):
		death_corpse.apply_hit_knock(impulse)
		return
	if not is_alive() and not is_death_physics():
		return
	if not is_alive():
		var death := get_node_or_null("Death")
		if death != null and death.has_method("buffer_knock"):
			death.buffer_knock(impulse)
		return
	_knockback_vel = impulse
	_knockback_timer = KNOCKBACK_TIMER_SEC
	if is_death_physics():
		velocity = impulse
	else:
		velocity += impulse
		floor_snap_length = 0.0


static func _knockback_impulse(knock_dir: Vector3) -> Vector3:
	var dir := knock_dir
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	else:
		dir = dir.normalized()
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	else:
		flat = flat.normalized()
	return flat * KNOCKBACK_HORIZONTAL + Vector3.UP * KNOCKBACK_UP


func _apply_knockback_bleed(delta: float) -> void:
	if _knockback_timer <= 0.0:
		return
	_knockback_timer -= delta
	velocity.x += _knockback_vel.x * KNOCKBACK_BLEED_PER_SEC * delta
	velocity.z += _knockback_vel.z * KNOCKBACK_BLEED_PER_SEC * delta
	_knockback_vel = _knockback_vel.move_toward(Vector3.ZERO, KNOCKBACK_DECAY * delta)


func _apply_character_color(color: Color) -> void:
	# Lit materials (no constant emission) so moonlight / world lights shade the mesh.
	if _body_mesh == null or _head_mesh == null:
		return
	var body_mat := _authored_material(_body_mesh)
	if body_mat != null:
		body_mat.albedo_color = color
	var head_mat := _authored_material(_head_mesh)
	if head_mat != null:
		head_mat.albedo_color = color.lightened(0.08)


func _authored_material(mesh_inst: MeshInstance3D) -> StandardMaterial3D:
	if mesh_inst == null:
		return null
	if mesh_inst.material_override is StandardMaterial3D:
		return mesh_inst.material_override as StandardMaterial3D
	var override_mat := mesh_inst.get_surface_override_material(0)
	if override_mat is StandardMaterial3D:
		return override_mat as StandardMaterial3D
	if mesh_inst.mesh != null and mesh_inst.mesh.get_surface_count() > 0:
		var surf := mesh_inst.mesh.surface_get_material(0)
		if surf is StandardMaterial3D:
			return surf as StandardMaterial3D
	return null


func _ensure_mesh_refs() -> void:
	if head == null:
		head = get_node_or_null("%Head") as Node3D
	if _body_mesh == null:
		_body_mesh = get_node_or_null("%Body") as MeshInstance3D
	if _head_mesh == null:
		_head_mesh = get_node_or_null("%HeadMesh") as MeshInstance3D
	if _body_collision == null:
		_body_collision = get_node_or_null("%CollisionShape3D") as CollisionShape3D


## Scenes without an authored Head/Eyes (the player) leave these empty and the
## glow helpers below become no-ops.
func _cache_eyes() -> void:
	_eyes_root = get_node_or_null("%Eyes") as Node3D
	if _eyes_root == null:
		_eyes_root = get_node_or_null("Head/Eyes") as Node3D
	_eye_meshes.clear()
	_eye_light = null
	if _eyes_root == null:
		return
	for child in _eyes_root.get_children():
		if child is MeshInstance3D:
			_eye_meshes.append(child as MeshInstance3D)
		elif child is OmniLight3D:
			_eye_light = child as OmniLight3D


func _apply_eye_glow_color(color: Color, energy_scale: float = 1.0) -> void:
	if _eyes_root == null:
		_cache_eyes()
	var mat: StandardMaterial3D = null
	if not _eye_meshes.is_empty():
		mat = _authored_material(_eye_meshes[0])
	if mat != null:
		mat.albedo_color = color
		mat.emission = color
		mat.emission_energy_multiplier = EYE_EMISSION_ENERGY * energy_scale
	if _eye_light != null:
		_eye_light.light_color = color
		_eye_light.light_energy = EYE_LIGHT_ENERGY * energy_scale
		_eye_light.light_cull_mask = WorldVisualLayersScript.SCENE_LIGHT_MASK


## Full HP = authored glow; near death = darker / dimmer.
func _apply_eye_glow_from_health() -> void:
	var t := 1.0 if Engine.is_editor_hint() else health_ratio()
	var dead := Color(
		eye_glow_color.r * EYE_DEAD_RGB_SCALE.x,
		eye_glow_color.g * EYE_DEAD_RGB_SCALE.y,
		eye_glow_color.b * EYE_DEAD_RGB_SCALE.z,
		1.0
	)
	var color := eye_glow_color.lerp(dead, 1.0 - t)
	var energy := lerpf(EYE_DEAD_ENERGY_SCALE, 1.0, t)
	_apply_eye_glow_color(color, energy)


func _set_chase_eyes_active(active: bool) -> void:
	_eyes_chasing = active
	_apply_eye_visibility()


func _apply_replicated_eyes() -> void:
	_apply_eye_visibility()
	_apply_eye_glow_from_health()


func _apply_eye_visibility() -> void:
	if _eyes_root == null:
		_cache_eyes()
	if _eyes_root != null:
		_eyes_root.visible = _eyes_chasing
