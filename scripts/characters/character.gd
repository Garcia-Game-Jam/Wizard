class_name Character
extends CharacterBody3D

## 3D character shell: body/head meshes, collision, tint, and the shared HP lifecycle.
## Inherited by PlayableCharacter (Apprentice), Monster, and Summon.
## Every character scene authors its own Health child, so each one manages an
## independent pool. Damage, healing, and death all run through that node: hits
## arrive via Character.apply_hit, and this class turns the resulting
## damaged / died signals into the shared reaction and teardown sequence.
## Subclasses vary only values and outcomes — see _on_hurt / _on_death / _combat_groups.
## CollisionShape3D is authored per character scene (Apprentice) — not rebuilt here.
## Appearance: mutate authored scene materials. Never allocate meshes or materials.

const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")
const HealthScript := preload("res://scripts/combat/health.gd")
const NetClockScript := preload("res://scripts/net/net_clock.gd")

const KNOCKBACK_TIMER_SEC := 0.35
const KNOCKBACK_HORIZONTAL := 9.0
const KNOCKBACK_UP := 3.5
const HURT_UP_IMPULSE := 5.0
const HURT_KNOCKBACK_TIMER_SEC := 0.15
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
	"Health:current_health",
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

## This character's own HP pool, resolved from the authored Health child.
## Reading it binds the lifecycle, so it works on a scene that is not in the tree yet.
var health: HealthScript:
	get:
		_bind_health()
		return _health

var net_phase: int = 0
var net_telegraph: float = 0.0
var _health: HealthScript = null
var _character_color: Color = Color.WHITE
var _knockback_vel: Vector3 = Vector3.ZERO
var _knockback_timer: float = 0.0
var _last_hit_dir: Vector3 = Vector3.FORWARD
var _body_collision: CollisionShape3D = null
var _eyes_root: Node3D = null
var _eye_meshes: Array[MeshInstance3D] = []
var _eye_light: OmniLight3D = null
var _eyes_chasing: bool = false

## Optional: scenes that author no Head/Body (test probes) leave these null and
## the appearance helpers below become no-ops.
@onready var head: Node3D = get_node_or_null("%Head") as Node3D
@onready var _body_mesh: MeshInstance3D = get_node_or_null("%Body") as MeshInstance3D
@onready var _head_mesh: MeshInstance3D = get_node_or_null("%HeadMesh") as MeshInstance3D


func _ready() -> void:
	_bind_health()
	call_deferred("_bind_rewindable")


func _bind_rewindable() -> void:
	pass


func _net_rewind_profile() -> String:
	return ""


func _bind_health() -> void:
	if _health != null and is_instance_valid(_health):
		return
	_health = get_node_or_null("Health") as HealthScript
	if _health == null:
		return
	if not _health.damaged.is_connected(_on_damaged):
		_health.damaged.connect(_on_damaged)
	if not _health.died.is_connected(_on_died):
		_health.died.connect(_on_died)
	if not _health.changed.is_connected(_on_health_changed):
		_health.changed.connect(_on_health_changed)


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
	var pool := health
	return pool != null and not pool.is_dead()


func health_ratio() -> float:
	var pool := health
	return pool.ratio() if pool != null else 1.0


## The one way damage reaches a body. Group scans and physics queries hand us
## arbitrary nodes; only a Character has a pool to spend, and its Health child
## raises damaged / died from there.
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
	character.health.take_damage(amount, from)


func _on_health_changed(_current: float, _maximum: float) -> void:
	_apply_eye_glow_from_health()


## Group scans hit nodes that may be freed or may not be characters at all
## (the lookdev player dummy). Only a real Character can be dead.
static func is_node_alive(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	if node is Character:
		return (node as Character).is_alive()
	return true


## Shared hit reaction: face away from the hit, hop, dim the eyes.
func _on_damaged(amount: float, from: Variant) -> void:
	var source := _live_source(from)
	_remember_hit_dir(source)
	_apply_hurt_knockback()
	_apply_eye_glow_from_health()
	_on_hurt(amount, source)


## Shared death teardown: stop moving, stop ticking, leave combat targeting.
func _on_died(from: Variant) -> void:
	velocity = Vector3.ZERO
	set_physics_process(false)
	for group in _combat_groups():
		if is_in_group(group):
			remove_from_group(group)
	_on_death(_live_source(from))


## Groups to leave on death. Monsters and summons drop out of AI targeting;
## players stay in "player" so respawn and spectating still resolve them.
func _combat_groups() -> Array[StringName]:
	return [&"combat_target"]


## Per-type hit reaction (combo triggers, hurt FX).
func _on_hurt(_amount: float, _from: Node3D) -> void:
	pass


## Per-type death outcome (corpse, ragdoll, respawn).
func _on_death(_from: Node3D) -> void:
	pass


## Undo death teardown after Health.revive(): move again and rejoin combat groups.
func restore_after_revive() -> void:
	set_physics_process(true)
	for group in _combat_groups():
		if not is_in_group(group):
			add_to_group(group)
	_apply_eye_glow_from_health()


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


func apply_fireball_knockback(fireball_dir: Vector3) -> void:
	if not is_alive():
		return
	if fireball_dir.length_squared() > 0.0001:
		_last_hit_dir = fireball_dir.normalized()
	var impulse := _fireball_knockback_impulse(fireball_dir)
	_knockback_vel = impulse
	_knockback_timer = KNOCKBACK_TIMER_SEC
	velocity += impulse


static func _fireball_knockback_impulse(fireball_dir: Vector3) -> Vector3:
	var dir := fireball_dir
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


func _apply_hurt_knockback() -> void:
	velocity.y = maxf(velocity.y, HURT_UP_IMPULSE)
	_knockback_vel.y = maxf(_knockback_vel.y, HURT_UP_IMPULSE * 0.45)
	_knockback_timer = maxf(_knockback_timer, HURT_KNOCKBACK_TIMER_SEC)


func _apply_knockback_bleed(delta: float) -> void:
	if _knockback_timer <= 0.0:
		return
	_knockback_timer -= delta
	velocity.x += _knockback_vel.x * 0.35
	velocity.z += _knockback_vel.z * 0.35
	_knockback_vel = _knockback_vel.move_toward(Vector3.ZERO, 28.0 * delta)


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


func get_snail_color() -> Color:
	return _character_color
