@tool
class_name EmberHaloAbility
extends "res://scripts/monsters/monster_ability.gd"

## Left-hand expanding halo ring: red ring above hand during windup.

const EmberHaloProjectileScript := preload(
	"res://scripts/monsters/abilities/ember_halo_projectile.gd"
)
const GameWorldScript := preload("res://scripts/game_world.gd")


func _ready() -> void:
	hand_side = HandSide.LEFT
	if ability_id.is_empty():
		ability_id = "ember_halo"
	if display_name == "Ability":
		display_name = "Ember Halo"
	telegraph_color = Color(1.0, 0.18, 0.08, 1.0)
	cooldown_sec = 7.5
	min_cast_range = 2.5
	max_cast_range = 11.0


func start_windup_fx(monster: Monster) -> void:
	stop_windup_fx()
	var hand := resolve_hand(monster)
	if hand == null:
		return
	_windup_fx = Node3D.new()
	_windup_fx.name = "EmberHaloWindup"
	_windup_fx.position = Vector3(0.0, 0.18, 0.0)
	hand.add_child(_windup_fx)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.06
	torus.outer_radius = 0.14
	torus.rings = 12
	torus.ring_segments = 20
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.2, 0.08, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.25, 0.1)
	mat.emission_energy_multiplier = 4.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	## TorusMesh already faces the ground plane (around +Y).
	ring.rotation_degrees = Vector3.ZERO
	_windup_fx.add_child(ring)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.25, 0.08)
	light.light_energy = 2.8
	light.omni_range = 1.3
	light.shadow_enabled = false
	_windup_fx.add_child(light)


func _fire_cast(monster: Monster, target: Node3D) -> void:
	if monster == null or target == null:
		return
	var parent := _projectile_parent(monster)
	var origin := resolve_cast_origin(monster)
	EmberHaloProjectileScript.spawn(parent, origin, target.global_position, monster)


func _projectile_parent(monster: Monster) -> Node:
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
