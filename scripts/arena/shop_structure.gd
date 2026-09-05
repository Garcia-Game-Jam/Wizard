@tool
class_name ShopStructure
extends Node3D

## Procedurally builds the shop encounter's solarium — an N-sided glazed
## pavilion on a raised stone-brick foundation, with dark-grey stone piers,
## walnut-wood arched fanlights, and a gold-trimmed glass pyramid roof, in
## the spirit of a grand estate conservatory. Modeled after
## colosseum_gate_ring.gd: every exported knob rebuilds the structure live
## in the editor, and _ready() rebuilds it fresh at load time too, so
## nothing generated here is baked into the .tscn that can drift out of
## sync with these values — generated nodes are deliberately NOT owned by
## the edited scene (unlike encounter_design_workshop.gd's markers, no
## piece here needs to be individually click-selected), so saving the scene
## never bloats it with stale generated geometry. The one exception is the
## door bay's entrance stairs (see below) — a hand-authored scene placed as
## an ordinary saved child instead, precisely because it DOES need to be
## individually click-editable, one step at a time.
##
## shop_displays (Array[ShopDisplayEntry]) places one stone-and-gold pedestal
## per entry — ShopDisplayN, one per configured bay — each with a floating
## icon and a "press F to buy" interaction (see shop_display_pedestal.gd for
## that half). Each entry is one of ShopDisplayEntry's concrete subclasses
## (SpellDisplayEntry, ArtifactDisplayEntry, HealDisplayEntry — see
## shop_display_entry.gd), picked via the Inspector's "New Resource" dialog.
##
## The whole structure (floor, piers, glazing, roof) sits foundation_riser
## above true ground (y=0) — a coursed stone-brick foundation wall (per
## FoundationN face, one per octagon side) fills that gap and keeps
## climbing to foundation_wall_fraction of the window-wall height above the
## new floor. door_bay_indices bays skip that face entirely instead (see
## _rebuild()'s own comment) — the stone kick wall would otherwise seal the
## doorway off below the doors, dead-ending the hand-authored entrance
## stairs against solid rock — so a door bay is open air from true ground
## all the way up, flanked by its two neighboring PierN corner wedges
## (_add_foundation_corner_fill) acting as the doorway's jambs. The stairs
## themselves (steps, landing, invisible ramp collision) are NOT generated
## here — unlike everything else in this file they're hand-authored as
## scenes/arenas/shop_entrance_stairs.tscn (a real, editable node tree) and
## placed as an ordinary child of this scene's root, rotated to the door
## bay's own angle; a new door bay needs its own instance placed the same
## way. Courses on the OTHER (solid) faces alternate a
## running-bond offset (odd rows start half a brick in) like real coursed
## masonry; each face is still a flat chord, so adjacent faces leave a small
## triangular notch at every PierN corner (regular-polygon geometry — see
## _add_foundation_corner_fill), plugged with one triangular prism per
## course, same stacked height as the bricks either side of it.
##
## door_bay_indices bays get a walkable double-door opening instead of fixed
## glazing — every other bay is solid, arched glass a player can't walk
## through. Each leaf hinges open on interact() (see shop_door.gd); collision
## lives on the leaf and disables itself once open, like ColosseumGate.
##
## Stone pieces (piers, capitals, foundation bricks/corner wedges, floor
## tiles) each get their own slightly different grey — see
## _ring_shades/_hash01 — so no two touching stone blocks share an
## identical shade, the way real quarried stone reads.
##
## Ivy (see scripts/environment/shop_ivy_builder.gd) climbs the foundation
## faces, corner wedges, and piers — patchy, thinning-out coverage rather
## than a hard line. Every leaf everywhere is one instance of a single
## MultiMeshInstance3D (see _build_ivy_multimesh) — ShopIvyBuilder.add_face
## doesn't create nodes at all, just appends a transform+color pair to a
## shared `batch` Dictionary threaded through the whole build, so however
## many thousand leaves a big structure grows, it's still one mesh, one
## material, one draw call. ivy_coverage only controls how thick the base
## (faces + corner wedges) grows; piers always grow at a fixed density
## (PIER_IVY_COVERAGE) and are only switched off entirely when
## ivy_coverage is 0 — the slider's exact value otherwise never changes
## them. Piers additionally have a chance to climb their full height
## rather than always stopping partway (see full_climb_chance).

const CollisionLayersScript := preload("res://scripts/collision_layers.gd")
const ShopFanMeshBuilderScript := preload("res://scripts/environment/shop_fan_mesh_builder.gd")
const IvyMeshBuilderScript := preload("res://scripts/environment/ivy_mesh_builder.gd")
const ShopIvyBuilderScript := preload("res://scripts/environment/shop_ivy_builder.gd")
const ShopDisplayPedestalScript := preload("res://scripts/arena/shop_display_pedestal.gd")
const ShopDoorScript := preload("res://scripts/arena/shop_door.gd")
## Preloaded rather than the bare "ShopDisplayEntry" class name — see
## combat_encounter.gd's identical note on MonsterSpawnEntryScript.
const ShopDisplayEntryScript := preload("res://scripts/arena/shop_display_entry.gd")
## The user's own shiny-gold material — shared as-is across every gold
## accent (roof ribs, fascia, finial, door handles, lantern) rather than
## reinvented as a plain Color, so tuning it in one place (or swapping the
## resource) retints the whole structure.
const GOLD_MATERIAL := preload("res://shiny_gold_color.tres")

## Per-piece stone lightness range — see _ring_shades/_stone_color.
const STONE_LOW := 0.15
const STONE_HIGH := 0.30
const STONE_TRIM_LOW := 0.34
const STONE_TRIM_HIGH := 0.46
const STONE_MIN_GAP := 0.035
## Piers always grow ivy at this fixed density (on/off only by whether
## ivy_coverage is >0 at all) — deliberately not the exported ivy_coverage
## value itself, so that slider only changes how dense the base looks.
const PIER_IVY_COVERAGE := 0.6
const WALNUT_COLOR := Color(0.22, 0.14, 0.09)
const GLASS_COLOR := Color(0.75, 0.85, 0.88, 0.35)
const LANTERN_GLOW_COLOR := Color(1.0, 0.85, 0.6)
## Player's capsule collision height (scenes/characters/character.tscn) —
## pedestals are sized off this so they read as counter-height fixtures next
## to the player rather than a disconnected magic number. _PEDESTAL_BASE_
## HEIGHT is the shaft+cap height _add_shop_display was originally hand-tuned
## to (0.7 shaft + 0.05 cap); PEDESTAL_SCALE shrinks every dimension in there
## uniformly so the built pedestal's real height lands on PEDESTAL_HEIGHT.
const PLAYER_HEIGHT := 0.72
const PEDESTAL_HEIGHT := PLAYER_HEIGHT * 0.8
const _PEDESTAL_BASE_HEIGHT := 0.75
const PEDESTAL_SCALE := PEDESTAL_HEIGHT / _PEDESTAL_BASE_HEIGHT

@export_range(3, 16, 1) var sides: int = 8:
	set(value):
		sides = value
		_rebuild()
@export_range(1.0, 40.0, 0.1, "suffix:m") var radius: float = 9.0:
	set(value):
		radius = value
		_rebuild()
@export_range(0.5, 20.0, 0.05, "suffix:m") var wall_height: float = 5.6:
	set(value):
		wall_height = value
		_rebuild()
## Rise of the rounded fanlight above wall_height (the eave/spring line).
@export_range(0.1, 10.0, 0.05, "suffix:m") var arch_rise: float = 2.6:
	set(value):
		arch_rise = value
		_rebuild()
## Rise of the glass pyramid roof above the eave (wall_height + arch_rise).
@export_range(0.5, 20.0, 0.05, "suffix:m") var roof_height: float = 6.0:
	set(value):
		roof_height = value
		_rebuild()
@export_range(0.0, 6.0, 0.05, "suffix:m") var roof_overhang: float = 0.8:
	set(value):
		roof_overhang = value
		_rebuild()
@export_range(0.05, 2.0, 0.01, "suffix:m") var floor_thickness: float = 0.3:
	set(value):
		floor_thickness = value
		_rebuild()
@export var pier_size: Vector2 = Vector2(0.9, 0.9):
	set(value):
		pier_size = value
		_rebuild()
@export_range(0.02, 1.0, 0.01, "suffix:m") var rib_thickness: float = 0.24:
	set(value):
		rib_thickness = value
		_rebuild()
@export_range(0.5, 10.0, 0.1, "suffix:m") var lantern_drop: float = 1.8:
	set(value):
		lantern_drop = value
		_rebuild()
## How far the whole building sits above true ground (y=0) on its stone
## foundation — default ~3 ft.
@export_range(0.0, 12.0, 0.01, "suffix:m") var foundation_riser: float = 0.9144:
	set(value):
		foundation_riser = value
		_rebuild()
## How far the stone-brick foundation keeps climbing above the raised floor,
## as a fraction of the window-wall height (wall_height + arch_rise) — "up
## to about where the windows are."
@export_range(0.0, 0.6, 0.01) var foundation_wall_fraction: float = 0.2:
	set(value):
		foundation_wall_fraction = value
		_rebuild()
@export_range(1, 6, 1) var foundation_courses: int = 3:
	set(value):
		foundation_courses = value
		_rebuild()
@export_range(1, 4, 1) var foundation_bricks_per_face: int = 2:
	set(value):
		foundation_bricks_per_face = value
		_rebuild()
@export_range(0.01, 0.3, 0.01, "suffix:m") var foundation_joint_gap: float = 0.05:
	set(value):
		foundation_joint_gap = value
		_rebuild()
## Scales the corner wedges' triangle base length — the auto-fitted
## tangential width (see _add_foundation_corner_fill) — 1.0 exactly closes
## the gap between two faces; below that leaves part of the rough seam
## showing, above that overlaps further into the bricks on either side.
@export_range(0.1, 3.0, 0.01) var foundation_corner_base_scale: float = 1.0:
	set(value):
		foundation_corner_base_scale = value
		_rebuild()
## Scales the corner wedges' triangle height — the apex-to-base distance,
## radially — independently of the base length above. 1.0 matches the
## foundation wall's own depth (flush with the bricks' inner/outer faces);
## below that the wedge sits shallower than the wall, above that it pokes
## past the bricks' inner or outer face.
@export_range(0.1, 3.0, 0.01) var foundation_corner_height_scale: float = 1.0:
	set(value):
		foundation_corner_height_scale = value
		_rebuild()
## How much ivy climbs the stone-brick foundation (faces and corner
## wedges) — 0 grows none, 1 is dense, patchy coverage climbing most of the
## way up. See ShopIvyBuilder.add_face.
@export_range(0.0, 3.0, 0.01) var ivy_coverage: float = 0.6:
	set(value):
		ivy_coverage = value
		_rebuild()
## Which bays (index i = the gap between PierI and PierI+1, going clockwise
## from north like colosseum_gate_ring.gd's angle numbering) get a walkable
## double-door opening instead of fixed glazing.
@export var door_bay_indices: Array[int] = [0]:
	set(value):
		door_bay_indices = value
		_rebuild()
## One stone-and-gold pedestal per entry — see ShopDisplayEntry for the
## per-pedestal bay/item fields, and shop_display_pedestal.gd for the
## floating icon + "press F to buy" interaction each one gets at runtime.
@export var shop_displays: Array[ShopDisplayEntryScript] = []:
	set(value):
		shop_displays = value
		_rebuild()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	_clear_prefixed(self, "Pier")
	_clear_prefixed(self, "Bay")
	_clear_prefixed(self, "Rib")
	_clear_prefixed(self, "ShopDisplay")
	_clear_prefixed(self, "Floor")
	_clear_prefixed(self, "RoofGlass")
	_clear_prefixed(self, "Fascia")
	_clear_prefixed(self, "Finial")
	_clear_prefixed(self, "Lantern")
	_clear_prefixed(self, "Foundation")
	_clear_prefixed(self, "Ivy")

	var floor_y := foundation_riser
	var window_zone_height := wall_height + arch_rise
	var foundation_top := floor_y + foundation_wall_fraction * window_zone_height
	var foundation_depth := pier_size.y * 1.6
	var eave_height := floor_y + window_zone_height
	var apex := Vector3(0.0, eave_height + roof_height, 0.0)
	var roof_radius := radius + roof_overhang
	var step_deg := 360.0 / float(sides)

	var pier_shades := _ring_shades(sides, STONE_LOW, STONE_HIGH)
	var capital_shades := _ring_shades(sides, STONE_TRIM_LOW, STONE_TRIM_HIGH)
	## Every ShopIvyBuilderScript.add_face call below appends into this
	## instead of creating nodes — see _build_ivy_multimesh, called once at
	## the end to turn the whole thing into a single draw call.
	var ivy_batch := {"transforms": [], "colors": []}

	_build_floor(floor_y)

	var base_points := PackedVector3Array()
	for i in sides:
		var pier_angle := i * step_deg
		_add_pier(
			i, pier_angle, foundation_top, eave_height, pier_shades[i], capital_shades[i], ivy_batch
		)
		_add_foundation_corner_fill(i, pier_angle, foundation_top, foundation_depth, ivy_batch)
		base_points.append(_ring_transform(pier_angle, roof_radius, eave_height).origin)
		_add_rib(i, base_points[i], apex)

	for i in sides:
		var bay_angle := i * step_deg + step_deg * 0.5
		var is_door := door_bay_indices.has(i)
		## A door bay carves straight through the stone kick wall instead of
		## sitting above it (see _add_foundation_face's own doc comment) —
		## skip the face entirely and drop the door's own base down to
		## floor_y so it reaches the true floor, flush with the hand-authored
		## entrance stairs' own landing (see this file's top-of-file doc
		## comment), instead of leaving a solid stone lip the stairs would
		## just run into.
		if not is_door:
			_add_foundation_face(i, bay_angle, foundation_top, foundation_depth, ivy_batch)
		var bay_base_y := floor_y if is_door else foundation_top
		_add_bay(i, bay_angle, bay_base_y, eave_height, is_door)
		for entry in shop_displays:
			if entry != null and entry.bay_index == i:
				_add_shop_display(i, bay_angle, floor_y, entry)

	_build_roof_glass(base_points, apex)
	_build_fascia(roof_radius, eave_height)
	_build_finial(apex)
	_build_lantern(apex)
	_build_ivy_multimesh(ivy_batch)


## --- Floor -------------------------------------------------------------


func _build_floor(floor_y: float) -> void:
	var floor_radius := radius + 0.5
	var body := StaticBody3D.new()
	body.name = "Floor"
	body.collision_layer = CollisionLayersScript.WORLD
	body.collision_mask = 0
	add_child(body)
	body.position = Vector3(0.0, floor_y - floor_thickness * 0.5, 0.0)

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := CylinderShape3D.new()
	shape.radius = floor_radius
	shape.height = floor_thickness
	collision.shape = shape
	body.add_child(collision)

	## Visual top surface only (nothing ever sees under the floor) — a fan
	## of `sides` flat wedges, one stone tile each, tinted per-wedge via
	## vertex color so no two touching tiles match.
	var step_deg := 360.0 / float(sides)
	var rim_points := PackedVector3Array()
	for i in sides:
		rim_points.append(_ring_transform(i * step_deg, floor_radius, floor_y).origin)
	var tile_shades := _ring_shades(sides, STONE_LOW, STONE_HIGH)
	var tile_colors := PackedColorArray()
	for value in tile_shades:
		tile_colors.append(_stone_color(value))

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "FloorMesh"
	mesh_instance.mesh = ShopFanMeshBuilderScript.build_pyramid(
		rim_points, Vector3(0.0, floor_y, 0.0), tile_colors
	)
	mesh_instance.material_override = _material(Color.WHITE, 0.85, 0.0, false, true)
	add_child(mesh_instance)


## --- Foundation (raised stone-brick base) ----------------------------------


## One coursed wall face, corner to corner (the full chord, not inset for
## the pier the way _add_bay's glazing is) — a grid of foundation_courses x
## foundation_bricks_per_face large stone blocks with a small mortar gap
## between them, each independently shaded (see _ring_shades' doc comment
## for why touching pieces never match). One collision box covers the whole
## face; the bricks themselves are visual only. _rebuild() skips this call
## entirely for door_bay_indices bays — the flanking PierN corner wedges
## (_add_foundation_corner_fill) stay put and read as the doorway's jambs,
## but the face between them stays open air so the hand-authored entrance
## stairs actually lead somewhere instead of dead-ending at a stone wall.
func _add_foundation_face(
	index: int, angle_deg_value: float, top_y: float, depth: float, ivy_batch: Dictionary
) -> void:
	var chord := 2.0 * radius * sin(deg_to_rad(180.0 / float(sides)))
	var body := StaticBody3D.new()
	body.name = "Foundation%d" % index
	body.collision_layer = CollisionLayersScript.WORLD
	body.collision_mask = 0
	add_child(body)
	body.transform = _ring_transform(angle_deg_value, radius, 0.0)

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = Vector3(chord, top_y, depth)
	collision.shape = shape
	collision.position = Vector3(0.0, top_y * 0.5, 0.0)
	body.add_child(collision)

	var brick_width := (
		(chord - foundation_joint_gap * (foundation_bricks_per_face - 1))
		/ float(foundation_bricks_per_face)
	)
	var course_height := (
		(top_y - foundation_joint_gap * (foundation_courses - 1)) / float(foundation_courses)
	)
	## Odd courses run staggered (running-bond) — offset half a brick from
	## the courses above/below, with a half-width brick at each end so the
	## row still spans the same face — instead of every joint lining up in
	## one unbroken vertical seam like the courses below/above it.
	for row in foundation_courses:
		var brick_y := row * (course_height + foundation_joint_gap) + course_height * 0.5
		var staggered := row % 2 == 1
		var half_width := brick_width * 0.5
		var col_count := foundation_bricks_per_face + 1 if staggered else foundation_bricks_per_face
		var brick_x := -chord * 0.5
		for col in col_count:
			var is_end_brick := staggered and (col == 0 or col == col_count - 1)
			var width := half_width if is_end_brick else brick_width
			var hashed := _hash01(float(index * 97 + row * 11 + col) * 3.71)
			var brick := MeshInstance3D.new()
			brick.name = "Brick%d_%d" % [row, col]
			var brick_mesh := BoxMesh.new()
			brick_mesh.size = Vector3(width, course_height, depth)
			brick.mesh = brick_mesh
			brick.material_override = _material(
				_stone_color(lerpf(STONE_LOW, STONE_HIGH, hashed)), 0.95, 0.0
			)
			brick.position = Vector3(brick_x + width * 0.5, brick_y, 0.0)
			body.add_child(brick)
			brick_x += width + foundation_joint_gap

	ShopIvyBuilderScript.add_face(
		body.transform, index, chord, depth, top_y, ivy_batch, ivy_coverage,
		top_y / float(foundation_courses)
	)


## A flat face panel is centered on its own bay bisector at `radius`, same
## as its neighbor — so at the shared corner, each panel's near end falls
## just short of the true polygon vertex (a chord's end sits inside the
## circumradius the piers sit on), leaving a small triangular notch. This
## derives that notch's exact tangential width from the polygon's own
## geometry (half_step = the angle from a pier to its bay's bisector) —
## scaled by foundation_corner_base_scale/foundation_corner_height_scale
## (1.0/1.0 = exact fit, tune either from the Inspector) — and fills it
## with one triangular prism per brick course — same stacked height as
## _add_foundation_face's bricks, each independently shaded so it doesn't
## match the bricks it sits between.
func _add_foundation_corner_fill(
	index: int, angle_deg_value: float, top_y: float, depth: float, ivy_batch: Dictionary
) -> void:
	var half_step := deg_to_rad(180.0 / float(sides))
	var wedge_width := (
		2.0
		* radius
		* sin(half_step)
		* (1.0 - cos(half_step))
		* foundation_corner_base_scale
	)
	if wedge_width < 0.01:
		return
	var wedge_depth := depth * foundation_corner_height_scale

	var body := StaticBody3D.new()
	body.name = "FoundationCorner%d" % index
	body.collision_layer = CollisionLayersScript.WORLD
	body.collision_mask = 0
	add_child(body)
	body.transform = _ring_transform(angle_deg_value, radius, 0.0)

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = Vector3(wedge_width, top_y, wedge_depth)
	collision.shape = shape
	collision.position = Vector3(0.0, top_y * 0.5, 0.0)
	body.add_child(collision)

	var course_height := (
		(top_y - foundation_joint_gap * (foundation_courses - 1)) / float(foundation_courses)
	)
	for row in foundation_courses:
		var brick_y := row * (course_height + foundation_joint_gap) + course_height * 0.5
		var mesh := PrismMesh.new()
		mesh.size = Vector3(wedge_width, wedge_depth, course_height)
		mesh.left_to_right = 0.5
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "Wedge%d" % row
		mesh_instance.mesh = mesh
		var hashed := _hash01(float(index * 53 + row * 7) * 5.19)
		mesh_instance.material_override = _material(
			_stone_color(lerpf(STONE_LOW, STONE_HIGH, hashed)), 0.95, 0.0
		)
		## Same axis remap as before: PrismMesh's triangular cross-section
		## lives in local XY, extruded along Z — rotate it so the triangle
		## lies flat (world XZ) and the prism extrudes vertically instead.
		mesh_instance.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		mesh_instance.position = Vector3(0.0, brick_y, 0.0)
		body.add_child(mesh_instance)

	## Corners are narrow, so only a light dusting — real ivy spreads across
	## a corner too, but doesn't need the same density as a full wall face.
	## full_climb_chance=1.0 (guaranteed): always reaches the top, so PierN
	## directly above always has ivy waiting right where its own vine
	## starts (see ShopIvyBuilder.add_face's doc comment) — a pier's ivy is
	## never disconnected from the base.
	ShopIvyBuilderScript.add_face(
		body.transform, index, wedge_width, wedge_depth, top_y, ivy_batch, ivy_coverage,
		top_y / float(foundation_courses), 0.4, 1.0
	)


## --- Ivy --------------------------------------------------------------


## Turns every leaf every ShopIvyBuilderScript.add_face call queued (across
## every foundation face, corner wedge, and pier) into one
## MultiMeshInstance3D — one mesh, one material, one draw call, however
## many thousand leaves the structure ends up growing. use_colors on the
## MultiMesh plus vertex_color_use_as_albedo on the shared material (see
## _material) is what lets each instance still carry its own independent
## shade despite sharing that one material.
func _build_ivy_multimesh(ivy_batch: Dictionary) -> void:
	var transforms: Array = ivy_batch["transforms"]
	if transforms.is_empty():
		return
	var colors: Array = ivy_batch["colors"]
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = IvyMeshBuilderScript.build_leaf()
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
		multimesh.set_instance_color(i, colors[i])

	var mesh_instance := MultiMeshInstance3D.new()
	mesh_instance.name = "Ivy"
	mesh_instance.multimesh = multimesh
	## Random per-leaf rotation means a leaf can just as easily face away
	## from the camera as toward it — double-sided so density doesn't
	## flicker (the vertex_color path in _material already disables culling).
	mesh_instance.material_override = _material(Color.WHITE, 0.85, 0.0, false, true)
	add_child(mesh_instance)


## --- Piers ---------------------------------------------------------------


## Starts at foundation_top (the stone-brick foundation already covers
## everything below that) and rises to eave_height, same as before.
func _add_pier(
	index: int,
	angle_deg_value: float,
	bottom_y: float,
	top_y: float,
	shade_value: float,
	capital_shade_value: float,
	ivy_batch: Dictionary
) -> void:
	var pier_height := top_y - bottom_y
	var center_y := bottom_y + pier_height * 0.5
	var body := StaticBody3D.new()
	body.name = "Pier%d" % index
	body.collision_layer = CollisionLayersScript.WORLD
	body.collision_mask = 0
	add_child(body)
	body.transform = _ring_transform(angle_deg_value, radius, center_y)

	var shaft := MeshInstance3D.new()
	shaft.name = "Shaft"
	var shaft_mesh := BoxMesh.new()
	shaft_mesh.size = Vector3(pier_size.x, pier_height, pier_size.y)
	shaft.mesh = shaft_mesh
	shaft.material_override = _material(_stone_color(shade_value), 0.88, 0.0)
	body.add_child(shaft)

	var shaft_collision := CollisionShape3D.new()
	shaft_collision.name = "CollisionShape3D"
	var shaft_shape := BoxShape3D.new()
	shaft_shape.size = shaft_mesh.size
	shaft_collision.shape = shaft_shape
	body.add_child(shaft_collision)

	## A slightly lighter stone cap finishing the pier top, just under the
	## eave/fascia line.
	var capital := MeshInstance3D.new()
	capital.name = "Capital"
	var capital_mesh := BoxMesh.new()
	capital_mesh.size = Vector3(pier_size.x + 0.28, 0.28, pier_size.y + 0.28)
	capital.mesh = capital_mesh
	capital.material_override = _material(_stone_color(capital_shade_value), 0.8, 0.0)
	capital.position = Vector3(0.0, pier_height * 0.5 - 0.14, 0.0)
	body.add_child(capital)

	## ShopIvyBuilder.add_face expects its anchor's local y=0 to be the
	## wall's bottom — body's own transform is centered at the pier's
	## vertical CENTER (see center_y above), so this shifts the frame down
	## to the pier's actual base before handing off (no node needed for it
	## now — just the composed Transform3D). Coverage is the fixed
	## PIER_IVY_COVERAGE, not ivy_coverage itself — only whether it's zero
	## or not (all ivy off) reaches the piers; the slider's exact value
	## never changes them. leaf_size_ref is deliberately the piers' own
	## (stable) cross-section, not pier_height/foundation_courses — a tall
	## pier has nothing to do with "brick course height", and dividing
	## width by a height-derived figure would round vine_count down to
	## zero on a tall, narrow pier (see add_face's doc comment). A generous
	## full_climb_chance is the "sometimes" in "ivy sometimes climbs the
	## entire pier" — most piers still stop partway up, same look as the
	## foundation.
	var ivy_anchor := body.transform * Transform3D(Basis(), Vector3(0.0, -pier_height * 0.5, 0.0))
	var pier_ivy_coverage := PIER_IVY_COVERAGE if ivy_coverage > 0.0 else 0.0
	var pier_leaf_size_ref := (pier_size.x + pier_size.y) * 0.5
	ShopIvyBuilderScript.add_face(
		ivy_anchor, index, pier_size.x, pier_size.y, pier_height, ivy_batch, pier_ivy_coverage,
		pier_leaf_size_ref, 1.0, 0.35
	)


## --- Bays (arched glazing/doors between two piers) ------------------------


func _add_bay(
	index: int, angle_deg_value: float, base_y: float, eave_height: float, is_door: bool
) -> void:
	var chord := 2.0 * radius * sin(deg_to_rad(180.0 / float(sides)))
	var bay_width := maxf(chord - pier_size.x, 0.4)
	var bay_depth := pier_size.y * 0.8
	var anchor := _ring_transform(angle_deg_value, radius, 0.0)
	var span_height := eave_height - base_y

	var root := Node3D.new()
	root.name = "Bay%d" % index
	add_child(root)
	root.transform = anchor

	if not is_door:
		## Fixed glazing above the stone foundation — solid, blocks a player
		## like any wall.
		var glazing := StaticBody3D.new()
		glazing.name = "Glazing"
		glazing.collision_layer = CollisionLayersScript.WORLD
		glazing.collision_mask = 0
		root.add_child(glazing)
		glazing.position = Vector3(0.0, base_y + span_height * 0.5, 0.0)
		_add_glass_pane(glazing, Vector3(bay_width * 0.94, span_height, 0.12), true)
	else:
		## Door bay: full-height glazed double doors reaching down to
		## base_y=floor_y (the true floor, not foundation_top — see
		## _rebuild()'s comment on why door bays skip the foundation face
		## entirely), reachable via the hand-authored entrance stairs and
		## landing (see this file's top-of-file doc comment). Each leaf
		## hangs off a hinge Node3D pivoting at its outer
		## (pier-side) edge, so ShopDoor can swing it open/closed on
		## interact() — see shop_door.gd. Collision (framed=true) lives on
		## the leaf itself and is disabled while open, matching
		## ColosseumGate's habit of not leaving a live shape behind an open
		## door.
		var leaf_width := (bay_width * 0.94) * 0.5
		var hinge_left: Node3D
		var hinge_right: Node3D
		for side_sign in [-1.0, 1.0]:
			var hinge := Node3D.new()
			hinge.name = "DoorHingeLeft" if side_sign < 0.0 else "DoorHingeRight"
			root.add_child(hinge)
			hinge.position = Vector3(side_sign * leaf_width, base_y + span_height * 0.5, 0.0)
			var leaf := Node3D.new()
			leaf.name = "DoorLeafLeft" if side_sign < 0.0 else "DoorLeafRight"
			hinge.add_child(leaf)
			leaf.position = Vector3(-side_sign * leaf_width * 0.5, 0.0, 0.0)
			_add_glass_pane(leaf, Vector3(leaf_width * 0.96, span_height, 0.12), true)
			var handle := MeshInstance3D.new()
			handle.name = "Handle"
			var handle_mesh := BoxMesh.new()
			handle_mesh.size = Vector3(0.08, 0.8, 0.12)
			handle.mesh = handle_mesh
			handle.material_override = GOLD_MATERIAL
			handle.position = Vector3(-side_sign * leaf_width * 0.42, 0.0, 0.12)
			leaf.add_child(handle)
			if side_sign < 0.0:
				hinge_left = hinge
			else:
				hinge_right = hinge
		var door := ShopDoorScript.new()
		door.name = "DoorController"
		door.configure(hinge_left, hinge_right)
		root.add_child(door)
	_add_mullion(root, base_y, eave_height)

	## Fanlight — a shallow, flattened hemisphere spanning the bay above the
	## eave line, echoing colosseum_gate.tscn's Crown+Dome arch language.
	## radius/height are set to the fanlight's real absolute width/rise
	## directly (no node scale on X/Y) — SphereMesh's is_hemisphere clip
	## puts the dome's apex at local y=height, not y=radius, so scaling a
	## unit hemisphere by `arch_rise` doubles it into an oversized dome.
	var fanlight := MeshInstance3D.new()
	fanlight.name = "Fanlight"
	var fanlight_radius := bay_width * 0.46
	var fanlight_mesh := SphereMesh.new()
	fanlight_mesh.radius = fanlight_radius
	fanlight_mesh.height = arch_rise
	fanlight_mesh.is_hemisphere = true
	fanlight.mesh = fanlight_mesh
	fanlight.material_override = _material(WALNUT_COLOR, 0.5, 0.05)
	## Z stays flattened (flush with the thin wall plane) via node scale —
	## only the depth axis, so it doesn't affect the already-correct
	## radius/height above.
	fanlight.scale = Vector3(1.0, 1.0, (bay_depth * 0.6) / fanlight_radius)
	fanlight.position = Vector3(0.0, eave_height, 0.0)
	root.add_child(fanlight)


func _add_mullion(root: Node3D, base_y: float, top_y: float) -> void:
	var mullion := MeshInstance3D.new()
	mullion.name = "Mullion"
	var mullion_mesh := BoxMesh.new()
	mullion_mesh.size = Vector3(0.16, top_y - base_y, 0.2)
	mullion.mesh = mullion_mesh
	mullion.material_override = _material(WALNUT_COLOR, 0.5, 0.05)
	mullion.position = Vector3(0.0, base_y + (top_y - base_y) * 0.5, 0.0)
	root.add_child(mullion)


func _add_glass_pane(parent: Node3D, size: Vector3, framed: bool) -> void:
	var pane := MeshInstance3D.new()
	pane.name = "Pane"
	var pane_mesh := BoxMesh.new()
	pane_mesh.size = size
	pane.mesh = pane_mesh
	pane.material_override = _material(GLASS_COLOR, 0.05, 0.1, true)
	parent.add_child(pane)
	if framed:
		var collision := CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		parent.add_child(collision)


## --- Roof ------------------------------------------------------------------


func _add_rib(index: int, base_point: Vector3, apex: Vector3) -> void:
	var rib := MeshInstance3D.new()
	rib.name = "Rib%d" % index
	var length := base_point.distance_to(apex)
	var rib_mesh := BoxMesh.new()
	rib_mesh.size = Vector3(rib_thickness, rib_thickness, length)
	rib.mesh = rib_mesh
	rib.material_override = GOLD_MATERIAL
	add_child(rib)
	rib.transform = _segment_transform(base_point, apex)


func _build_roof_glass(base_points: PackedVector3Array, apex: Vector3) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "RoofGlass"
	mesh_instance.mesh = ShopFanMeshBuilderScript.build_pyramid(base_points, apex)
	mesh_instance.material_override = _material(GLASS_COLOR, 0.05, 0.1, true)
	add_child(mesh_instance)


func _build_fascia(roof_radius: float, eave_height: float) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Fascia"
	var mesh := CylinderMesh.new()
	mesh.top_radius = roof_radius
	mesh.bottom_radius = roof_radius
	mesh.height = 0.3
	mesh.radial_segments = sides
	mesh_instance.mesh = mesh
	mesh_instance.material_override = GOLD_MATERIAL
	mesh_instance.position = Vector3(0.0, eave_height, 0.0)
	add_child(mesh_instance)


func _build_finial(apex: Vector3) -> void:
	var finial := MeshInstance3D.new()
	finial.name = "Finial"
	var mesh := SphereMesh.new()
	mesh.radius = 0.32
	mesh.height = 0.64
	finial.mesh = mesh
	finial.material_override = GOLD_MATERIAL
	finial.position = apex
	add_child(finial)


## --- Lantern ---------------------------------------------------------------


func _build_lantern(apex: Vector3) -> void:
	var root := Node3D.new()
	root.name = "Lantern"
	add_child(root)
	root.position = apex

	var chain := MeshInstance3D.new()
	chain.name = "Chain"
	var chain_mesh := CylinderMesh.new()
	chain_mesh.top_radius = 0.03
	chain_mesh.bottom_radius = 0.03
	chain_mesh.height = lantern_drop
	chain.mesh = chain_mesh
	chain.material_override = GOLD_MATERIAL
	chain.position = Vector3(0.0, -lantern_drop * 0.5, 0.0)
	root.add_child(chain)

	var body := MeshInstance3D.new()
	body.name = "Body"
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.44
	body_mesh.bottom_radius = 0.44
	body_mesh.height = 0.64
	body_mesh.radial_segments = 6
	body.mesh = body_mesh
	body.material_override = GOLD_MATERIAL
	body.position = Vector3(0.0, -lantern_drop, 0.0)
	root.add_child(body)

	var cap := MeshInstance3D.new()
	cap.name = "Cap"
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 0.0
	cap_mesh.bottom_radius = 0.52
	cap_mesh.height = 0.44
	cap_mesh.radial_segments = 6
	cap.mesh = cap_mesh
	cap.material_override = GOLD_MATERIAL
	cap.position = Vector3(0.0, -lantern_drop + 0.54, 0.0)
	root.add_child(cap)

	var glow := OmniLight3D.new()
	glow.name = "Glow"
	glow.light_color = LANTERN_GLOW_COLOR
	glow.light_energy = 0.8
	glow.omni_range = 12.0
	glow.position = Vector3(0.0, -lantern_drop, 0.0)
	root.add_child(glow)


## --- Shop displays -------------------------------------------------------


## A stone plinth with gold cap/base rings — sits on the raised floor, not
## true ground — topped by a ShopDisplayPedestal child (shop_display_
## pedestal.gd) that owns the floating icon and the "press F to buy"
## interaction itself; this function only builds the static stone/gold
## geometry underneath it.
func _add_shop_display(
	index: int, bay_angle_value: float, floor_y: float, entry: ShopDisplayEntryScript
) -> void:
	var pedestal_height := 0.7 * PEDESTAL_SCALE
	var shaft_bottom_radius := 0.22 * PEDESTAL_SCALE
	var shaft_top_radius := 0.16 * PEDESTAL_SCALE
	var cap_height := 0.05 * PEDESTAL_SCALE
	var cap_extra_radius := 0.06 * PEDESTAL_SCALE
	var base_ring_extra_radius := 0.07 * PEDESTAL_SCALE
	var base_ring_height := 0.06 * PEDESTAL_SCALE

	var body := StaticBody3D.new()
	body.name = "ShopDisplay%d" % index
	body.collision_layer = CollisionLayersScript.WORLD
	body.collision_mask = 0
	add_child(body)
	body.transform = _ring_transform(bay_angle_value, radius * 0.72, floor_y)

	var shaft := MeshInstance3D.new()
	shaft.name = "Shaft"
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = shaft_top_radius
	shaft_mesh.bottom_radius = shaft_bottom_radius
	shaft_mesh.height = pedestal_height
	shaft_mesh.radial_segments = 12
	shaft.mesh = shaft_mesh
	var hashed := _hash01(float(index) * 143.9 + 21.0)
	shaft.material_override = _material(_stone_color(lerpf(STONE_LOW, STONE_HIGH, hashed)), 0.85, 0.0)
	shaft.position = Vector3(0.0, pedestal_height * 0.5, 0.0)
	body.add_child(shaft)

	var shaft_collision := CollisionShape3D.new()
	shaft_collision.name = "CollisionShape3D"
	var shaft_shape := CylinderShape3D.new()
	shaft_shape.radius = shaft_bottom_radius
	shaft_shape.height = pedestal_height
	shaft_collision.shape = shaft_shape
	shaft_collision.position = shaft.position
	body.add_child(shaft_collision)

	var cap := MeshInstance3D.new()
	cap.name = "Cap"
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = shaft_top_radius + cap_extra_radius
	cap_mesh.bottom_radius = shaft_top_radius + cap_extra_radius
	cap_mesh.height = cap_height
	cap_mesh.radial_segments = 12
	cap.mesh = cap_mesh
	cap.material_override = GOLD_MATERIAL
	cap.position = Vector3(0.0, pedestal_height + cap_height * 0.5, 0.0)
	body.add_child(cap)

	var base_ring := MeshInstance3D.new()
	base_ring.name = "BaseRing"
	var base_ring_mesh := CylinderMesh.new()
	base_ring_mesh.top_radius = shaft_bottom_radius + base_ring_extra_radius
	base_ring_mesh.bottom_radius = shaft_bottom_radius + base_ring_extra_radius
	base_ring_mesh.height = base_ring_height
	base_ring_mesh.radial_segments = 12
	base_ring.mesh = base_ring_mesh
	base_ring.material_override = GOLD_MATERIAL
	base_ring.position = Vector3(0.0, base_ring_height * 0.5, 0.0)
	body.add_child(base_ring)

	var pedestal := ShopDisplayPedestalScript.new()
	pedestal.name = "Display"
	pedestal.configure(entry)
	pedestal.position = Vector3(0.0, pedestal_height + cap_height, 0.0)
	body.add_child(pedestal)


## --- Shared helpers ---------------------------------------------------


func _material(
	color: Color,
	roughness: float,
	metallic: float,
	transparent: bool = false,
	vertex_color: bool = false
) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	if transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if vertex_color:
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## A hint of cool blue-grey tint on top of a plain lightness value — reads
## as natural quarried stone rather than a flat painted grey.
static func _stone_color(value: float) -> Color:
	return Color(value * 0.97, value, value * 1.04)


## Deterministic pseudo-random value in [0, 1) for a given seed — stays
## identical across rebuilds, unlike RandomNumberGenerator, so tuning an
## unrelated export doesn't reshuffle every stone's shade.
static func _hash01(n: float) -> float:
	return absf(fmod(sin(n * 12.9898 + 78.233) * 43758.5453, 1.0))


## One grey/lightness value per ring position (piers, capitals, floor
## tiles). A single hash pass can still land two ring-adjacent values close
## together by chance, so a second pass nudges any pair (including the wrap
## from the last entry back to the first) that's under STONE_MIN_GAP apart
## toward opposite ends of the range — guarantees no two touching stone
## pieces read as the same shade, without the result looking like a
## repeating pattern.
static func _ring_shades(count: int, low: float, high: float) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	for i in count:
		values.append(lerpf(low, high, _hash01(float(i) * 91.345)))
	for i in count:
		var next_i := (i + 1) % count
		if absf(values[i] - values[next_i]) < STONE_MIN_GAP:
			values[next_i] = low if values[next_i] >= (low + high) * 0.5 else high
	return values


func _clear_prefixed(parent: Node, prefix: String) -> void:
	var doomed: Array[Node] = []
	for child in parent.get_children():
		if child.name.begins_with(prefix):
			doomed.append(child)
	for child in doomed:
		parent.remove_child(child)
		child.free()


## Local -Z of the returned transform points toward the structure's center —
## same convention as colosseum_gate_ring.gd's _ring_transform.
static func _ring_transform(angle_deg_value: float, r: float, y: float) -> Transform3D:
	var rad := deg_to_rad(angle_deg_value)
	var basis := Basis(Vector3.UP, rad)
	var pos := Vector3(r * sin(rad), y, r * cos(rad))
	return Transform3D(basis, pos)


static func _segment_transform(from: Vector3, to: Vector3) -> Transform3D:
	var mid := (from + to) * 0.5
	var dir := to - from
	var length := dir.length()
	if length < 0.0001:
		return Transform3D(Basis(), mid)
	return Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), mid)
