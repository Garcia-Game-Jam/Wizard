@tool
class_name MonsterAbility
extends Node3D

## Base for authored combat abilities under Monster/Abilities/.
## Scene-tree source of truth — cast FX attach to monster hands when present.

enum HandSide { RIGHT, LEFT }

const WINDUP_SEC_DEFAULT := 0.55
const MonsterAIScript := preload("res://scripts/monsters/monster_ai.gd")

@export var ability_id: String = ""
@export var display_name: String = "Ability"
@export_multiline var description: String = ""
@export_range(0.0, 60.0, 0.1) var cooldown_sec: float = 5.0
@export_range(0.1, 3.0, 0.05) var windup_sec: float = WINDUP_SEC_DEFAULT
@export var telegraph_color: Color = Color(1.0, 0.3, 0.1, 1.0)
@export var hand_side: HandSide = HandSide.RIGHT
## When false, ability can cast without a player target (ambient summons).
@export var requires_target: bool = true
## When true, needs a chase interest target but ignores range bands.
@export var requires_chase_target: bool = false
@export_range(0.0, 30.0, 0.1) var min_cast_range: float = 3.0
@export_range(0.0, 40.0, 0.1) var max_cast_range: float = 12.0
## When false, ability is excluded from cast rotation (e.g. chase reposition dashes).
@export var participates_in_cast_rotation: bool = true

@export_tool_button("Preview Cast", "Callable")
var preview_cast_action := preview_cast

var _cooldown_left: float = 0.0
var _windup_fx: Node3D = null


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(0.0, _cooldown_left - delta)


func get_hand_side() -> HandSide:
	return hand_side


func can_cast() -> bool:
	return _cooldown_left <= 0.0 and is_inside_tree()


func is_ready_to_cast(monster: Monster, target: Node3D) -> bool:
	if not can_cast():
		return false
	if not requires_target:
		return true
	var live := MonsterAIScript.live_node3d(target)
	if requires_chase_target:
		return live != null
	return is_target_in_range(monster, live)


func is_target_in_range(monster: Monster, target: Node3D) -> bool:
	if not requires_target:
		return true
	if requires_chase_target:
		return target != null
	if monster == null or target == null:
		return false
	var dist := flat_distance_to(monster, target)
	return dist >= min_cast_range and dist <= max_cast_range


func preferred_cast_range() -> float:
	return (min_cast_range + max_cast_range) * 0.5


func flat_distance_to(monster: Monster, target: Node3D) -> float:
	if monster == null or target == null:
		return 0.0
	var flat := Vector3(
		target.global_position.x - monster.global_position.x,
		0.0,
		target.global_position.z - monster.global_position.z
	)
	return flat.length()


func begin_cooldown() -> void:
	_cooldown_left = maxf(0.0, cooldown_sec)


func reset_cooldown() -> void:
	_cooldown_left = 0.0


## Combo opener: clear cooldown and any ability-specific cast locks.
func reset_for_combo() -> void:
	reset_cooldown()


## Combo runner: fire immediately without range/cooldown gates.
func fire_combo_step(monster: Monster, target: Node3D) -> void:
	reset_for_combo()
	fire_instant(monster, target)


## Combo runner: release a held charge regardless of normal gates.
func release_combo_step(monster: Monster, target: Node3D) -> void:
	reset_for_combo()
	release_charge(monster, target)


## Override: attach windup VFX to the correct hand.
func start_windup_fx(monster: Monster) -> void:
	stop_windup_fx()
	var hand := resolve_hand(monster)
	if hand == null:
		return
	_windup_fx = _build_default_windup_fx()
	hand.add_child(_windup_fx)


func stop_windup_fx() -> void:
	if _windup_fx != null and is_instance_valid(_windup_fx):
		_windup_fx.queue_free()
	_windup_fx = null


## Override to spawn combat projectile. Called after windup completes (legacy cast path).
func begin_cast(monster: Monster, target: Node3D) -> void:
	stop_windup_fx()
	begin_cooldown()
	_fire_cast(monster, target)


## Caster combat: release a held charge — fire the spell and start cooldown.
func release_charge(monster: Monster, target: Node3D) -> void:
	stop_windup_fx()
	begin_cooldown()
	_fire_cast(monster, target)


## Combo / bypass path — no windup, immediate fire + cooldown when off CD.
func fire_instant(monster: Monster, target: Node3D) -> void:
	if not can_cast() or monster == null:
		return
	_fire_cast(monster, target)
	begin_cooldown()


func preview_cast() -> void:
	reset_cooldown()
	reset_for_combo()
	var monster := _find_monster()
	start_windup_fx(monster)
	var tree := get_tree()
	if tree == null:
		stop_windup_fx()
		return
	await tree.create_timer(windup_sec).timeout
	if not is_inside_tree():
		return
	if monster == null or not is_instance_valid(monster):
		stop_windup_fx()
		return
	var target := resolve_preview_target(monster)
	var ephemeral: Node3D = null
	if target == null:
		ephemeral = _spawn_ephemeral_preview_target(monster)
		target = ephemeral
	reset_cooldown()
	fire_instant(monster, target)
	if ephemeral != null and is_instance_valid(ephemeral):
		ephemeral.queue_free()
	stop_windup_fx()


func resolve_preview_target(_monster: Monster) -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("player"):
		if not (node is Node3D) or not Character.is_node_alive(node):
			continue
		return node as Node3D
	return null


func resolve_hand(monster: Monster) -> Node3D:
	if monster == null:
		return null
	var path := "%RightHand" if hand_side == HandSide.RIGHT else "%LeftHand"
	var hand := monster.get_node_or_null(path) as Node3D
	if hand != null:
		return hand
	var fallbacks := [
		"Body/Hands/RightHand" if hand_side == HandSide.RIGHT else "Body/Hands/LeftHand",
		"MidBody/Hands/RightHand" if hand_side == HandSide.RIGHT else "MidBody/Hands/LeftHand",
	]
	for fallback in fallbacks:
		hand = monster.get_node_or_null(fallback) as Node3D
		if hand != null:
			return hand
	return null


func resolve_cast_origin(monster: Monster) -> Vector3:
	var hand := resolve_hand(monster)
	if hand != null:
		return hand.global_position
	if monster != null:
		return monster.global_position + Vector3(0.0, 0.55, 0.0)
	return global_position


func _fire_cast(_monster: Monster, _target: Node3D) -> void:
	pass


func _spawn_ephemeral_preview_target(monster: Monster) -> Node3D:
	var dummy := Node3D.new()
	var parent: Node = monster.get_parent()
	if parent == null:
		parent = monster
	parent.add_child(dummy)
	dummy.global_position = (
		monster.global_position + (-monster.global_transform.basis.z * 6.0)
	)
	return dummy


func _find_monster() -> Monster:
	var n: Node = self
	while n != null:
		if n is Monster:
			return n as Monster
		n = n.get_parent()
	return null


func _build_default_windup_fx() -> Node3D:
	var root := Node3D.new()
	root.name = "WindupFx"
	var sphere := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.16
	sphere.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(telegraph_color.r, telegraph_color.g, telegraph_color.b, 0.7)
	mat.emission_enabled = true
	mat.emission = telegraph_color
	mat.emission_energy_multiplier = 3.5
	sphere.material_override = mat
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sphere)
	var light := OmniLight3D.new()
	light.light_color = telegraph_color
	light.light_energy = 2.4
	light.omni_range = 1.2
	light.shadow_enabled = false
	root.add_child(light)
	return root


func _exit_tree() -> void:
	stop_windup_fx()
