class_name RelicClone
extends Node3D

## Visual decoy of the delivery relic. Targetable, pullable, Dispell-destroyable.
## Does not complete the delivery objective or allow pickup.

const SpellWorldSyncScript := preload("res://scripts/spells/spell_world_sync.gd")
const HoveringOrbMotionScript := preload("res://scripts/spells/hovering_orb_motion.gd")
const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")
const PlaceholderPingAudioScript := preload("res://scripts/objectives/placeholder_ping_audio.gd")

const GROUP_NAME := SpellWorldSyncScript.KIND_RELIC_CLONE
const PLACE_HEIGHT := HoveringOrbMotionScript.HEIGHT_RELIC
const PING_INTERVAL_SEC := 3.5
const DESPAWN_FADE_SEC := 0.45
const ORB_RADIUS := 0.28

var spawn_id := ""

var _hover_base := Vector3.ZERO
var _hover_phase := 0.0
var _hovering := false
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _audio: AudioStreamPlayer3D
var _ping_timer := 0.0
var _despawning := false
var _despawn_tween: Tween


static func spawn(
	parent: Node,
	world_position: Vector3,
	clone_spawn_id: String = ""
) -> Node3D:
	var decoy = new()
	decoy.spawn_id = clone_spawn_id
	parent.add_child(decoy)
	var snapped_pos := snap_to_ground(decoy.get_world_3d(), world_position)
	decoy._hover_base = snapped_pos
	decoy.global_position = snapped_pos
	decoy._hovering = true
	return decoy


static func snap_to_ground(world_3d: World3D, pos: Vector3) -> Vector3:
	return HoveringOrbMotionScript.snap_base(world_3d, pos, PLACE_HEIGHT)


func _ready() -> void:
	if spawn_id.is_empty():
		spawn_id = SpellWorldSyncScript.make_spawn_id()
	SpellWorldSyncScript.register(self, SpellWorldSyncScript.KIND_RELIC_CLONE, spawn_id)
	_build_visuals()
	_hover_phase = randf() * TAU
	_ping_timer = randf() * PING_INTERVAL_SEC


func get_spell_world_kind() -> String:
	return SpellWorldSyncScript.KIND_RELIC_CLONE


func get_spell_world_id() -> String:
	return spawn_id


func get_hover_base() -> Vector3:
	return _hover_base


func spell_set_guided_position(world_pos: Vector3, lock_to_ground: bool = true) -> void:
	var snapped_pos := world_pos
	if lock_to_ground and is_inside_tree():
		snapped_pos = snap_to_ground(get_world_3d(), world_pos)
	_hover_base = snapped_pos
	if _hovering:
		global_position = HoveringOrbMotionScript.visual_from_base(_hover_base, _hover_phase)
	else:
		global_position = _hover_base


func destroy_from_spell(from_network: bool = false) -> void:
	if _despawning or not is_inside_tree():
		return
	_despawning = true
	_hovering = false
	if not from_network:
		SpellWorldSyncScript.broadcast_event(self, SpellWorldSyncScript.EVENT_REMOVE)
	_begin_despawn_fade()


func _process(delta: float) -> void:
	if _despawning:
		return
	if _hovering:
		_hover_phase = HoveringOrbMotionScript.advance_bob_phase(_hover_phase, delta)
		global_position = HoveringOrbMotionScript.visual_from_base(_hover_base, _hover_phase)
	_ping_timer += delta
	if _ping_timer >= PING_INTERVAL_SEC:
		_ping_timer = 0.0
		if _audio != null and is_instance_valid(_audio):
			_audio.play()


func _build_visuals() -> void:
	var item_shape := SphereMesh.new()
	item_shape.radius = ORB_RADIUS
	item_shape.height = ORB_RADIUS * 2.0
	_mesh = MeshInstance3D.new()
	_mesh.mesh = item_shape
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.95, 0.78, 0.22)
	_mat.emission_enabled = true
	_mat.emission = Color(0.95, 0.65, 0.15) * 0.8
	_mesh.material_override = _mat
	_mesh.layers = WorldVisualLayersScript.WORLD
	add_child(_mesh)

	_audio = AudioStreamPlayer3D.new()
	_audio.stream = PlaceholderPingAudioScript.create_stream()
	_audio.max_distance = 28.0
	_audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(_audio)


func _begin_despawn_fade() -> void:
	if is_in_group(GROUP_NAME):
		remove_from_group(GROUP_NAME)
	if is_in_group(SpellWorldSyncScript.GROUP_NAME):
		remove_from_group(SpellWorldSyncScript.GROUP_NAME)
	if _despawn_tween != null and _despawn_tween.is_valid():
		_despawn_tween.kill()
	if _mat == null:
		queue_free()
		return
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if _mesh != null:
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var clear := Color(_mat.albedo_color.r, _mat.albedo_color.g, _mat.albedo_color.b, 0.0)
	_despawn_tween = create_tween()
	_despawn_tween.set_trans(Tween.TRANS_SINE)
	_despawn_tween.set_ease(Tween.EASE_IN)
	_despawn_tween.tween_property(_mat, "albedo_color", clear, DESPAWN_FADE_SEC)
	_despawn_tween.tween_callback(queue_free)
