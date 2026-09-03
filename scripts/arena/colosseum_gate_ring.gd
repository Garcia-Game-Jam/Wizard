@tool
class_name ColosseumGateRing
extends Node3D

## Places one gate model — scenes/arenas/colosseum_gate.tscn — around the arena
## as many times as angles_deg has entries, instead of hand-authoring a separate
## node tree (and transform) per gate. For each angle this also places the
## matching wall doorway notch, spawn pad, and SpawnTelegraph light cluster —
## one shared angle array drives all four, so a monster's spawn pad, its
## telegraph glow, and the gate that opens for it can never end up facing a
## different way or a different spot than each other.
##
## Runs in the editor (@tool) so the ring rebuilds live as you tune it. Gate
## nodes are named GateN — SpawnTelegraph finds them via gates_root_path
## pointed at this node, and drives their door open/close alongside the glow.
##
## Generated nodes are deliberately ownerless (never saved into the .tscn) —
## angles_deg/radius/*_root_path here are the only source of truth, so there
## is nothing baked-in that can drift out of sync with them. _ready() rebuilds
## everything fresh every time the scene loads, in the editor and in-game alike.

const GateScene := preload("res://scenes/arenas/colosseum_gate.tscn")
const CollisionLayersScript := preload("res://scripts/collision_layers.gd")

## One entry per gate, in world degrees (0 = +Z/"north", 90 = +X/"east", ...).
## Index N produces GateN/PadN/SpotN/OmniN/BeamN/RingN — order matters where
## SpawnTelegraph/ArenaEncounters expect a specific pad index to release from a
## specific gate.
@export var angles_deg: PackedFloat32Array = PackedFloat32Array(
	[234.4623, 125.5377, 54.4623, 305.5377, 90.0, 180.0, 270.0, 0.0]
):
	set(value):
		angles_deg = value
		_rebuild()

@export_range(1.0, 200.0, 0.1, "suffix:m") var radius: float = 27.0:
	set(value):
		radius = value
		_rebuild()

## Ring wall CSGShape3D to also cut a doorway through, at the same angles.
## Leave empty to only place gates (no wall notch generation).
@export_node_path("CSGShape3D") var wall_ring_path: NodePath:
	set(value):
		wall_ring_path = value
		_rebuild()

@export_group("Wall cutter")
@export var cutter_size: Vector3 = Vector3(3.4, 10.0, 6.0):
	set(value):
		cutter_size = value
		_rebuild()
## Radius the cutter is centered on — should land mid-thickness of the ring wall.
@export_range(1.0, 200.0, 0.1, "suffix:m") var cutter_radius: float = 28.25:
	set(value):
		cutter_radius = value
		_rebuild()
@export var cutter_y: float = 0.0:
	set(value):
		cutter_y = value
		_rebuild()

@export_group("Spawn pads")
## Where ArenaEncounters' dumps actually land — inside radius (a gate standing
## in front of the wall) so a spawned monster reads as having just come through
## the gate that opened for it, not appearing in open floor.
@export_node_path("Node3D") var pads_root_path: NodePath:
	set(value):
		pads_root_path = value
		_rebuild()
@export_range(1.0, 200.0, 0.1, "suffix:m") var pad_radius: float = 25.0:
	set(value):
		pad_radius = value
		_rebuild()
@export var pad_y: float = 0.05:
	set(value):
		pad_y = value
		_rebuild()

@export_group("Spawn zone")
## Platform + spawn marker behind each gate — outside the wall, where a
## colosseum monster actually appears (PadN above stays put as the inner
## telegraph light's anchor, not a spawn point, once this is set).
##
## zone_radius/zone_size default to a near (inward) edge of 27.5m — just
## inside arena_bulls.tscn's Colosseum/Floor radius (28.0m) — so the platform
## overlaps the arena floor by half a meter instead of leaving a gap over the
## void at the doorway. The far edge sits 5m further out (halved from the
## original 10m depth so a spawned monster has little room to loiter behind
## its gate and is pushed to walk out into the arena almost immediately).
## Retune both if a future arena's floor radius differs — keep the near edge
## the same (27.5) and only move the far edge/center to change depth again.
@export_node_path("Node3D") var spawn_zones_root_path: NodePath:
	set(value):
		spawn_zones_root_path = value
		_rebuild()
@export_range(1.0, 200.0, 0.1, "suffix:m") var zone_radius: float = 30.0:
	set(value):
		zone_radius = value
		_rebuild()
@export var zone_size: Vector3 = Vector3(6.0, 0.6, 5.0):
	set(value):
		zone_size = value
		_rebuild()
## Match the arena floor's own material so the platform reads as part of the
## same floor rather than a separate white default-material slab dropped on
## top of it.
@export var zone_material: Material:
	set(value):
		zone_material = value
		_rebuild()
@export var zone_spawn_y: float = 0.05:
	set(value):
		zone_spawn_y = value
		_rebuild()
## Invisible guard walls on the platform's left, right, and far (outward)
## edges — the near edge, facing the gate, is deliberately left open so a
## spawned monster's only way off the platform is through the gate toward
## the arena center.
@export_range(0.5, 20.0, 0.1, "suffix:m") var zone_wall_height: float = 3.0:
	set(value):
		zone_wall_height = value
		_rebuild()
@export_range(0.05, 2.0, 0.05, "suffix:m") var zone_wall_thickness: float = 0.3:
	set(value):
		zone_wall_thickness = value
		_rebuild()

@export_group("Telegraph lights")
## SpawnTelegraph node — SpotN/OmniN/BeamN/RingN are authored as ITS direct
## children (spawn_telegraph.gd looks them up unqualified), not this node's.
@export_node_path("Node3D") var telegraph_root_path: NodePath:
	set(value):
		telegraph_root_path = value
		_rebuild()
@export var beam_mesh: Mesh:
	set(value):
		beam_mesh = value
		_rebuild()
@export var beam_material: Material:
	set(value):
		beam_material = value
		_rebuild()
@export var ring_mesh: Mesh:
	set(value):
		ring_mesh = value
		_rebuild()
@export var ring_material: Material:
	set(value):
		ring_material = value
		_rebuild()
@export var spot_height: float = 21.0:
	set(value):
		spot_height = value
		_rebuild()
@export var omni_height: float = 2.4:
	set(value):
		omni_height = value
		_rebuild()
@export var beam_height: float = 10.5:
	set(value):
		beam_height = value
		_rebuild()
@export var ring_height: float = 0.08:
	set(value):
		ring_height = value
		_rebuild()

const SPOT_COLOR := Color(1.0, 0.92, 0.7, 1.0)
const SPOT_RANGE := 32.0
const SPOT_ATTENUATION := 0.2
const SPOT_ANGLE := 24.0
const OMNI_COLOR := Color(1.0, 0.88, 0.55, 1.0)
const OMNI_RANGE := 9.0
const OMNI_ATTENUATION := 0.2


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	_clear_prefixed(self, "Gate")
	var ring := _wall_ring()
	if ring != null:
		_clear_prefixed(ring, "GateCut")
	var pads := _pads_root()
	if pads != null:
		_clear_prefixed(pads, "Pad")
	var zones := _spawn_zones_root()
	if zones != null:
		## "Zone" also matches ZoneWallLeftN/ZoneWallRightN/ZoneWallBackN below —
		## one prefix clears the platform, its guard walls, and stragglers alike.
		_clear_prefixed(zones, "Zone")
		_clear_prefixed(zones, "SpawnPoint")
	var telegraph := _telegraph_root()
	if telegraph != null:
		for prefix in ["Spot", "Omni", "Beam", "Ring"]:
			_clear_prefixed(telegraph, prefix)
	for i in angles_deg.size():
		var angle: float = angles_deg[i]
		_add_gate(i, angle)
		if ring != null:
			_add_cutter(ring, i, angle)
		if pads != null:
			_add_pad(pads, i, angle)
		if zones != null:
			_add_spawn_zone(zones, i, angle)
		if telegraph != null:
			_add_telegraph_cluster(telegraph, i, angle)


func _add_gate(index: int, angle_deg_value: float) -> void:
	var gate := GateScene.instantiate()
	gate.name = "Gate%d" % index
	add_child(gate)
	gate.transform = _ring_transform(angle_deg_value, radius, 0.0)


func _add_cutter(ring: Node, index: int, angle_deg_value: float) -> void:
	var cutter := CSGMesh3D.new()
	cutter.name = "GateCut%d" % index
	var mesh := BoxMesh.new()
	mesh.size = cutter_size
	cutter.mesh = mesh
	cutter.operation = CSGShape3D.OPERATION_SUBTRACTION
	ring.add_child(cutter)
	cutter.transform = _ring_transform(angle_deg_value, cutter_radius, cutter_y)


func _add_pad(pads: Node, index: int, angle_deg_value: float) -> void:
	var pad := Marker3D.new()
	pad.name = "Pad%d" % index
	pads.add_child(pad)
	pad.transform = _ring_transform(angle_deg_value, pad_radius, pad_y)


## A walkable floor slab plus a Marker3D at its center, both just outside the
## wall — the doorway notch (_add_cutter) already opens the wall out to
## roughly this radius, so the slab sits flush against that opening with the
## gate as its only way into the arena.
func _add_spawn_zone(zones: Node, index: int, angle_deg_value: float) -> void:
	var floor_slab := CSGBox3D.new()
	floor_slab.name = "Zone%d" % index
	floor_slab.size = zone_size
	floor_slab.use_collision = true
	floor_slab.collision_layer = CollisionLayersScript.WORLD
	floor_slab.collision_mask = 0
	floor_slab.material = zone_material
	zones.add_child(floor_slab)
	floor_slab.transform = _ring_transform(angle_deg_value, zone_radius, -zone_size.y * 0.5)

	var spawn_point := Marker3D.new()
	spawn_point.name = "SpawnPoint%d" % index
	zones.add_child(spawn_point)
	spawn_point.transform = _ring_transform(angle_deg_value, zone_radius, zone_spawn_y)

	## Left/right/back guard walls — everywhere but the near (gate-facing,
	## -Z-local) edge, so the only way off the platform is through the gate.
	var half_x := zone_size.x * 0.5
	var half_z := zone_size.z * 0.5
	var half_h := zone_wall_height * 0.5
	_add_zone_wall(
		zones, "ZoneWallLeft%d" % index, angle_deg_value,
		Vector3(-half_x, half_h, 0.0),
		Vector3(zone_wall_thickness, zone_wall_height, zone_size.z)
	)
	_add_zone_wall(
		zones, "ZoneWallRight%d" % index, angle_deg_value,
		Vector3(half_x, half_h, 0.0),
		Vector3(zone_wall_thickness, zone_wall_height, zone_size.z)
	)
	_add_zone_wall(
		zones, "ZoneWallBack%d" % index, angle_deg_value,
		Vector3(0.0, half_h, half_z),
		## A little wider than the platform so it seals the two back corners
		## against the left/right walls instead of leaving pinhole gaps.
		Vector3(zone_size.x + zone_wall_thickness, zone_wall_height, zone_wall_thickness)
	)


## local_offset is measured in the platform's own frame, anchored where
## _add_spawn_zone anchors the floor slab: +X tangential, +Z away from the
## arena center (see _ring_transform's doc comment), +Y up from the floor.
func _add_zone_wall(
	zones: Node,
	wall_name: String,
	angle_deg_value: float,
	local_offset: Vector3,
	box_size: Vector3
) -> void:
	var wall := CSGBox3D.new()
	wall.name = wall_name
	wall.size = box_size
	wall.visible = false
	wall.use_collision = true
	wall.collision_layer = CollisionLayersScript.WORLD
	wall.collision_mask = 0
	zones.add_child(wall)
	var anchor := _ring_transform(angle_deg_value, zone_radius, 0.0)
	wall.transform = Transform3D(anchor.basis, anchor.origin + anchor.basis * local_offset)


func _add_telegraph_cluster(telegraph: Node, index: int, angle_deg_value: float) -> void:
	var spot := SpotLight3D.new()
	spot.name = "Spot%d" % index
	spot.light_color = SPOT_COLOR
	spot.light_energy = 0.0
	spot.spot_range = SPOT_RANGE
	spot.spot_attenuation = SPOT_ATTENUATION
	spot.spot_angle = SPOT_ANGLE
	telegraph.add_child(spot)
	spot.transform = _ring_transform(angle_deg_value, pad_radius, spot_height)

	var omni := OmniLight3D.new()
	omni.name = "Omni%d" % index
	omni.light_color = OMNI_COLOR
	omni.light_energy = 0.0
	omni.omni_range = OMNI_RANGE
	omni.omni_attenuation = OMNI_ATTENUATION
	telegraph.add_child(omni)
	omni.transform = _ring_transform(angle_deg_value, pad_radius, omni_height)

	var beam := MeshInstance3D.new()
	beam.name = "Beam%d" % index
	beam.visible = false
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.mesh = beam_mesh
	beam.material_override = beam_material
	telegraph.add_child(beam)
	beam.transform = _ring_transform(angle_deg_value, pad_radius, beam_height)

	var ring_deco := MeshInstance3D.new()
	ring_deco.name = "Ring%d" % index
	ring_deco.visible = false
	ring_deco.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring_deco.mesh = ring_mesh
	ring_deco.material_override = ring_material
	telegraph.add_child(ring_deco)
	ring_deco.transform = _ring_transform(angle_deg_value, pad_radius, ring_height)


func _wall_ring() -> Node:
	if wall_ring_path.is_empty():
		return null
	return get_node_or_null(wall_ring_path)


func _pads_root() -> Node:
	if pads_root_path.is_empty():
		return null
	return get_node_or_null(pads_root_path)


func _spawn_zones_root() -> Node:
	if spawn_zones_root_path.is_empty():
		return null
	return get_node_or_null(spawn_zones_root_path)


func _telegraph_root() -> Node:
	if telegraph_root_path.is_empty():
		return null
	return get_node_or_null(telegraph_root_path)


func _clear_prefixed(parent: Node, prefix: String) -> void:
	var doomed: Array[Node] = []
	for child in parent.get_children():
		if child.name.begins_with(prefix):
			doomed.append(child)
	for child in doomed:
		parent.remove_child(child)
		child.free()


## Local -Z of the returned transform points toward the ring's center — build
## the gate/cutter's "into the arena" side on that face.
static func _ring_transform(angle_deg_value: float, r: float, y: float) -> Transform3D:
	var rad := deg_to_rad(angle_deg_value)
	var basis := Basis(Vector3.UP, rad)
	var pos := Vector3(r * sin(rad), y, r * cos(rad))
	return Transform3D(basis, pos)
