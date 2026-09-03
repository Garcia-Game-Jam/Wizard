class_name SpawnTelegraphFx
extends Node3D

## Position-based "yellow light" spawn telegraph — a downward spotlight +
## ground omni + translucent beam + glow ring, all fading in together then
## held at full brightness. Used for level-driven monster spawns, which land
## at an arbitrary authored world position rather than a fixed pad index the
## way scripts/arena/spawn_telegraph.gd's SpotN/OmniN/BeamN/RingN are — see
## arena_scene.gd's _play_spawn_telegraph_fx()/rpc_show_telegraph(). Visuals
## intentionally match that pad-based cluster (colosseum_gate_ring.gd's
## _add_telegraph_cluster, arena.tscn's hand-authored Spot0-3/etc.) so a
## level-driven spawn reads the same as a classic one.
##
## Fades in over fade_sec, then holds — closing is always instant, matching
## the pad-based system's own quirk-but-consistent behavior: the light never
## fades OUT, it just vanishes the moment the monster actually spawns. The
## owner (arena_scene.gd) frees this node at that point; nothing in here
## times its own removal.

const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")

const SPOT_COLOR := Color(1.0, 0.92, 0.7, 1.0)
const SPOT_RANGE := 32.0
const SPOT_ATTENUATION := 0.2
const SPOT_ANGLE := 24.0
const SPOT_HEIGHT := 21.0
const ENERGY_SPOT := 48.0

const OMNI_COLOR := Color(1.0, 0.88, 0.55, 1.0)
const OMNI_RANGE := 9.0
const OMNI_ATTENUATION := 0.2
const OMNI_HEIGHT := 2.4
const ENERGY_OMNI := 10.0

const BEAM_COLOR := Color(0.89, 0.67, 0.26, 0.55)
const BEAM_TOP_RADIUS := 1.1
const BEAM_BOTTOM_RADIUS := 1.6
const BEAM_HEIGHT := 21.0
const BEAM_Y := 10.5
const BEAM_EMISSION := 2.4

const RING_COLOR := Color(0.89, 0.67, 0.26, 0.85)
const RING_RADIUS := 1.8
const RING_MESH_HEIGHT := 0.08
const RING_Y := 0.08
const RING_EMISSION := 3.2

@export var fade_sec: float = 0.2

var _elapsed := 0.0
var _energy := 0.0
var _spot: SpotLight3D
var _omni: OmniLight3D
var _beam: MeshInstance3D
var _ring: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D


func _ready() -> void:
	_spot = SpotLight3D.new()
	_spot.light_color = SPOT_COLOR
	_spot.light_energy = 0.0
	_spot.spot_range = SPOT_RANGE
	_spot.spot_attenuation = SPOT_ATTENUATION
	_spot.spot_angle = SPOT_ANGLE
	_spot.shadow_enabled = false
	_spot.light_cull_mask = WorldVisualLayersScript.SCENE_LIGHT_MASK
	add_child(_spot)
	_spot.position = Vector3(0.0, SPOT_HEIGHT, 0.0)
	## look_at(down) is degenerate with Vector3.UP; -Z must be world down.
	_spot.basis = Basis.looking_at(Vector3.DOWN, Vector3.FORWARD)

	_omni = OmniLight3D.new()
	_omni.light_color = OMNI_COLOR
	_omni.light_energy = 0.0
	_omni.omni_range = OMNI_RANGE
	_omni.omni_attenuation = OMNI_ATTENUATION
	_omni.shadow_enabled = false
	_omni.light_cull_mask = WorldVisualLayersScript.SCENE_LIGHT_MASK
	add_child(_omni)
	_omni.position = Vector3(0.0, OMNI_HEIGHT, 0.0)

	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = BEAM_TOP_RADIUS
	beam_mesh.bottom_radius = BEAM_BOTTOM_RADIUS
	beam_mesh.height = BEAM_HEIGHT
	beam_mesh.radial_segments = 12
	beam_mesh.rings = 1
	_beam_mat = _make_material()
	_beam = MeshInstance3D.new()
	_beam.mesh = beam_mesh
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.layers = WorldVisualLayersScript.WORLD
	add_child(_beam)
	_beam.position = Vector3(0.0, BEAM_Y, 0.0)

	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = RING_RADIUS
	ring_mesh.bottom_radius = RING_RADIUS
	ring_mesh.height = RING_MESH_HEIGHT
	ring_mesh.radial_segments = 20
	ring_mesh.rings = 1
	_ring_mat = _make_material()
	_ring = MeshInstance3D.new()
	_ring.mesh = ring_mesh
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.layers = WorldVisualLayersScript.WORLD
	add_child(_ring)
	_ring.position = Vector3(0.0, RING_Y, 0.0)

	_apply_energy(0.0)


func _make_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	return mat


func _process(delta: float) -> void:
	if _energy >= 1.0:
		set_process(false)
		return
	_elapsed += delta
	_energy = clampf(_elapsed / maxf(fade_sec, 0.001), 0.0, 1.0)
	_apply_energy(_energy)


func _apply_energy(amount: float) -> void:
	_spot.light_energy = ENERGY_SPOT * amount
	_omni.light_energy = ENERGY_OMNI * amount
	_beam.visible = amount > 0.02
	_ring.visible = amount > 0.02
	var beam_color := BEAM_COLOR
	beam_color.a = BEAM_COLOR.a * amount
	_beam_mat.albedo_color = beam_color
	_beam_mat.emission = Color(BEAM_COLOR.r, BEAM_COLOR.g, BEAM_COLOR.b, 1.0)
	_beam_mat.emission_energy_multiplier = BEAM_EMISSION * amount
	var ring_color := RING_COLOR
	ring_color.a = RING_COLOR.a * amount
	_ring_mat.albedo_color = ring_color
	_ring_mat.emission = Color(RING_COLOR.r, RING_COLOR.g, RING_COLOR.b, 1.0)
	_ring_mat.emission_energy_multiplier = RING_EMISSION * amount
