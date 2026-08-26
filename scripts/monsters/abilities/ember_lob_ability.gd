@tool
class_name EmberLobAbility
extends "res://scripts/monsters/monster_ability.gd"

## Right-hand lob fireball: red glow + smoke windup, arc then dive at player.

const EmberLobProjectileScript := preload(
	"res://scripts/monsters/abilities/ember_lob_projectile.gd"
)
const GameWorldScript := preload("res://scripts/game_world.gd")

@export var smoke_puff_count: int = 10


func _ready() -> void:
	hand_side = HandSide.RIGHT
	if ability_id.is_empty():
		ability_id = "ember_lob"
	if display_name == "Ability":
		display_name = "Ember Lob"
	telegraph_color = Color(1.0, 0.22, 0.06, 1.0)
	cooldown_sec = 5.0
	min_cast_range = 3.5
	max_cast_range = 13.0


func start_windup_fx(monster: Monster) -> void:
	stop_windup_fx()
	var hand := resolve_hand(monster)
	if hand == null:
		return
	_windup_fx = Node3D.new()
	_windup_fx.name = "EmberLobWindup"
	hand.add_child(_windup_fx)

	var glow := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.1
	mesh.height = 0.2
	glow.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.2, 0.05)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.15, 0.02)
	mat.emission_energy_multiplier = 5.0
	glow.material_override = mat
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_windup_fx.add_child(glow)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.25, 0.05)
	light.light_energy = 3.8
	light.omni_range = 1.6
	light.shadow_enabled = false
	_windup_fx.add_child(light)

	var smoke := GPUParticles3D.new()
	smoke.amount = smoke_puff_count
	smoke.lifetime = 0.5
	smoke.emitting = true
	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(0, 1, 0)
	pmat.spread = 50.0
	pmat.initial_velocity_min = 0.3
	pmat.initial_velocity_max = 0.9
	pmat.gravity = Vector3(0, 1.2, 0)
	pmat.scale_min = 0.06
	pmat.scale_max = 0.14
	pmat.color = Color(0.2, 0.18, 0.16, 0.7)
	smoke.process_material = pmat
	var smesh := SphereMesh.new()
	smesh.radius = 0.05
	smesh.height = 0.1
	smoke.draw_pass_1 = smesh
	_windup_fx.add_child(smoke)


func _fire_cast(monster: Monster, target: Node3D) -> void:
	if monster == null or target == null:
		return
	var parent := _projectile_parent(monster)
	var origin := resolve_cast_origin(monster)
	EmberLobProjectileScript.spawn(parent, origin, target, monster)


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
