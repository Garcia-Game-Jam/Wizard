class_name SpawnTelegraph
extends Node3D

## Ceiling spots + floor pools that mark monster pads. The lit pad set is an
## RPC intent (requested_mask), not rewindable state — netfox restores
## pad_mask from history and would otherwise zero the tell every tick.
##
## Optional GateN children (scripts/arena/colosseum_gate.gd) open on a
## separate, slower lifecycle than the light glow (gate_mask/_gate_energy,
## driven by open_gates()/close_all_gates()) — a gate drops slowly while its
## light is telegraphing, then stays down through the whole round instead of
## snapping shut the instant a monster spawns. It only closes — instantly —
## when the next round's staging calls close_all_gates(), and any gate that
## round reuses immediately starts dropping again. Arenas without gates
## simply have no GateN nodes. GateN is looked up under gates_root_path when
## set (e.g. a ColosseumGateRing that generates them), else as a direct child
## of this node.

const NetClockScript := preload("res://scripts/net/net_clock.gd")
const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")

const ENERGY_SPOT := 48.0
const ENERGY_OMNI := 10.0
const FADE_SEC := 0.2
## Deliberately much slower than FADE_SEC — the door itself should read as a
## heavy, grinding drop, not a snappy light-glow fade.
const GATE_OPEN_SEC := 2.2

@export var gates_root_path: NodePath

## RPC/host intent. Not in net_state_paths; rewind must not wipe it.
var requested_mask: int = 0
var pad_mask: int = 0
var spot_energy: float = 0.0
var _display_energy: float = 0.0

## Which gate indices are currently open (down) — set by open_gates(), only
## ever cleared (all at once) by close_all_gates(). Same "RPC intent, not
## rewindable" shape as requested_mask above; purely cosmetic, so it never
## needs to be netfox state.
var gate_mask: int = 0
var _gate_energy: float = 0.0

var _spots: Array[SpotLight3D] = []
var _omnis: Array[OmniLight3D] = []
var _beams: Array[MeshInstance3D] = []
var _rings: Array[MeshInstance3D] = []
var _beam_mats: Array[StandardMaterial3D] = []
var _ring_mats: Array[StandardMaterial3D] = []
var _gates: Array[Node] = []


func _ready() -> void:
	_cache_spots()
	_aim_spots_down()
	_apply_visuals()
	_apply_gate_visuals()


func _process(delta: float) -> void:
	_tick_display(delta)
	_tick_gates(delta)


func _physics_process(delta: float) -> void:
	if NetClockScript.is_ticking():
		return
	_rollback_tick(delta, 0, true)


func net_state_paths() -> Array[String]:
	return [
		":pad_mask",
		":spot_energy",
	]


func show_pads(pads: PackedInt32Array) -> void:
	var mask := 0
	for pad in pads:
		if pad >= 0 and pad < 32:
			mask |= 1 << pad
	requested_mask = mask
	pad_mask = mask


func clear_pads() -> void:
	requested_mask = 0
	pad_mask = 0


## Starts these gate indices dropping (slowly) and holds them down — call
## once when a round's telegraph goes up. Does not affect gates already open
## from a still-live round; close_all_gates() is the only way to shut a gate.
func open_gates(pads: PackedInt32Array) -> void:
	var mask := 0
	for pad in pads:
		if pad >= 0 and pad < 32:
			mask |= 1 << pad
	gate_mask |= mask


## Snaps every open gate shut instantly — call once at the start of the next
## round's staging, before that round's own open_gates() call.
func close_all_gates() -> void:
	gate_mask = 0
	_gate_energy = 0.0
	_apply_gate_visuals()


func _rollback_tick(delta: float, _tick: int, _is_fresh: bool) -> void:
	## History restore can zero pad_mask; re-apply the RPC intent first.
	pad_mask = requested_mask
	var target := 1.0 if pad_mask != 0 else 0.0
	if FADE_SEC <= 0.0:
		spot_energy = target
	else:
		spot_energy = move_toward(spot_energy, target, delta / FADE_SEC)


func _tick_display(delta: float) -> void:
	var target := 1.0 if requested_mask != 0 else 0.0
	if FADE_SEC <= 0.0:
		_display_energy = target
	else:
		_display_energy = move_toward(_display_energy, target, delta / FADE_SEC)
	_apply_visuals()


func _cache_spots() -> void:
	_spots.clear()
	_omnis.clear()
	_beams.clear()
	_rings.clear()
	_beam_mats.clear()
	_ring_mats.clear()
	_gates.clear()
	var gates_root := _resolve_gates_root()
	var i := 0
	while true:
		var spot := get_node_or_null("Spot%d" % i) as SpotLight3D
		if spot == null:
			break
		_spots.append(spot)
		_configure_light(spot)
		var omni := get_node_or_null("Omni%d" % i) as OmniLight3D
		if omni != null:
			_configure_light(omni)
		_omnis.append(omni)
		var beam := get_node_or_null("Beam%d" % i) as MeshInstance3D
		_beams.append(beam)
		_beam_mats.append(_local_mat(beam))
		var ring := get_node_or_null("Ring%d" % i) as MeshInstance3D
		_rings.append(ring)
		_ring_mats.append(_local_mat(ring))
		_gates.append(gates_root.get_node_or_null("Gate%d" % i) if gates_root != null else null)
		i += 1


func _resolve_gates_root() -> Node:
	if gates_root_path.is_empty():
		return self
	return get_node_or_null(gates_root_path)


func _configure_light(light: Light3D) -> void:
	light.light_cull_mask = WorldVisualLayersScript.SCENE_LIGHT_MASK
	light.shadow_enabled = false
	light.light_specular = 0.35


func _local_mat(mesh: MeshInstance3D) -> StandardMaterial3D:
	if mesh == null:
		return null
	mesh.layers = WorldVisualLayersScript.WORLD
	var mat := mesh.material_override as StandardMaterial3D
	if mat == null:
		return null
	mat = mat.duplicate() as StandardMaterial3D
	mesh.material_override = mat
	mat.emission_enabled = true
	return mat


func _aim_spots_down() -> void:
	for spot in _spots:
		## look_at(down) is degenerate with Vector3.UP; -Z must be world down.
		spot.basis = Basis.looking_at(Vector3.DOWN, Vector3.FORWARD)


func _apply_visuals() -> void:
	if _spots.is_empty():
		_cache_spots()
	var lit := clampf(_display_energy, 0.0, 1.0)
	for i in _spots.size():
		var on := (requested_mask & (1 << i)) != 0
		var amount := lit if on else 0.0
		_spots[i].light_energy = ENERGY_SPOT * amount
		if i < _omnis.size() and _omnis[i] != null:
			_omnis[i].light_energy = ENERGY_OMNI * amount
		_set_mesh_amount(_beams, _beam_mats, i, amount, 0.55, 2.4)
		_set_mesh_amount(_rings, _ring_mats, i, amount, 0.85, 3.2)


func _tick_gates(delta: float) -> void:
	var target := 1.0 if gate_mask != 0 else 0.0
	if GATE_OPEN_SEC <= 0.0:
		_gate_energy = target
	else:
		_gate_energy = move_toward(_gate_energy, target, delta / GATE_OPEN_SEC)
	_apply_gate_visuals()


func _apply_gate_visuals() -> void:
	if _gates.is_empty():
		_cache_spots()
	var opening := clampf(_gate_energy, 0.0, 1.0)
	for i in _gates.size():
		if _gates[i] == null or not _gates[i].has_method("set_open_amount"):
			continue
		## A gate not in gate_mask snaps shut immediately (close_all_gates is
		## meant to be instant); one still in gate_mask rides the slow ramp.
		var on := (gate_mask & (1 << i)) != 0
		_gates[i].call("set_open_amount", opening if on else 0.0)


func _set_mesh_amount(
	meshes: Array[MeshInstance3D],
	mats: Array[StandardMaterial3D],
	index: int,
	amount: float,
	alpha: float,
	emission: float
) -> void:
	if index >= meshes.size() or meshes[index] == null:
		return
	meshes[index].visible = amount > 0.02
	if index >= mats.size() or mats[index] == null:
		return
	var color := mats[index].albedo_color
	color.a = alpha * amount
	mats[index].albedo_color = color
	mats[index].emission = Color(color.r, color.g, color.b, 1.0)
	mats[index].emission_energy_multiplier = emission * amount
