class_name ShopEntranceStairsBuilder
extends RefCounted

## Builds one door bay's entrance: a rectangular landing right at the
## threshold, spanning the full width of the glazed doors themselves (see
## build()'s landing_width), reached by a double grand staircase of
## individually floating rectangular stone step-bricks — two mirrored
## flights that start from the landing's own left and right edges (not
## dead center beneath it) and fan outward in a straight line down to true
## ground (y=0), each flight its own single unbending diagonal — a
## widening trapezoid below the landing rather than a curved sweep — with
## an open gap between the two flights (landing_width wide at the landing,
## widening further from there) that a real split double staircase has.
## Split out of shop_structure.gd only
## because that file hit gdlint's per-file line cap — otherwise as tightly
## coupled to it as if this were still inline (every call is keyed into the
## caller's own index/hash space via _hash01, ShopStructure.STONE_LOW/HIGH
## and STONE_TRIM_LOW/HIGH are duplicated below rather than passed in or
## preloaded back, matching ShopIvyBuilder's identical note on
## IVY_LOW/HIGH).
##
## Without these, a door bay is unreachable from outside: the raised
## foundation (see ShopStructure's own top-of-file doc comment) has no ramp
## or stair of its own. Steps never touch — each is its own slab, STEP_RISE
## apart vertically from the last in its flight, and radially apart by
## whatever run that same vertical rise needs to match the ramp's own
## slope (see STEP_RISE's own doc comment). A flight's lateral offset from
## the shared center axis starts at landing_half_width (flush with the
## landing's own edge) and grows in a straight line with how far down the
## flight a step is, reaching landing_half_width +
## FLIGHT_LATERAL_SPREAD apart at the ground. No ivy here (tried it, looked
## bad) — each step just gets its own hashed shade within [STONE_LOW,
## STONE_HIGH], the same per-piece-variety trick as the foundation bricks.
##
## Steps carry no collision of their own — each is its own separate
## floating slab, not a continuous surface, so hopping the actual bricks
## would mean jumping (or sliding back down) between every one regardless
## of the angle they sit at. One straight ramp collision (_build_ramp)
## stands in for each flight instead — a single continuous box run from the
## landing's outer edge down to below true ground along the *exact same
## straight line* the flight's own steps drift along (see
## FLIGHT_LATERAL_SPREAD), at the same slope angle those steps are placed
## at too (see STEP_RISE's own doc comment) so it always reads as walkable
## floor and lines up with the visible bricks instead of overshooting or
## undershooting them. Because both the flight and its ramp are straight
## lines (not curves), one rigid box can follow the ramp's line exactly
## with no seams to catch a foot on (an earlier version tried tracking a
## curved fan with a chain of short angled segments, and the seam between
## every pair of segments read as a tiny bump the player would hop on) —
## and because each ramp is only as wide as its own flight, the two ramps
## leave the same open gap between them (landing_width at the landing,
## widening toward the ground) that the visible steps do. Walk into that
## gap and there's nothing underfoot, same as there's nothing to see — a
## player who does falls through to true ground, into the open space under
## the stairs. Only the landing keeps its own flat collision.

const CollisionLayersScript := preload("res://scripts/collision_layers.gd")

const STONE_LOW := 0.15
const STONE_HIGH := 0.30
const STONE_TRIM_LOW := 0.34
const STONE_TRIM_HIGH := 0.46

## Vertical rise per step — sized against the player's own capsule (~0.72m
## tall, see player.tscn) so a single step reads as a modest step-up rather
## than something the player has to climb over. How far each step runs
## (horizontally, along the flight) isn't a fixed constant alongside this
## one — build() derives it from whatever slope angle the ramp itself is
## using (ramp_config's "angle_deg", see _build_ramp), so the visible
## bricks are always placed along the exact same incline the ramp beneath
## them actually is, however that's tuned.
const STEP_RISE := 0.16
const STEP_THICKNESS := 0.09
const LANDING_DEPTH := 0.9
## How far the bottommost step of each flight sinks below where STEP_RISE
## would otherwise put it, so it reads as embedded into true ground instead
## of floating a hair above it with a thin shadow gap underneath.
const LAST_STEP_SINK := 0.05
## How much further sideways (beyond landing_half_width, its starting
## offset at the landing — see build()) each flight drifts by the time it
## reaches the ground — in a straight line, not a curve, so a flight's
## lateral position at any point is exactly proportional to how far it's
## descended (see _build_flight and _build_ramp, which both walk this same
## line).
const FLIGHT_LATERAL_SPREAD := 2.0
const FLIGHT_WIDTH := 0.28
const FLIGHT_DEPTH := 0.22

## The ramp's own slope, independent of the steps' visual 45° — comfortably
## under floor_max_angle's default 45° so it always reads as walkable floor,
## not a wall. Its ground-level end is pushed out past the last visible
## step (see _build_ramp) by whatever extra run that shallower angle needs
## to still reach the same floor_y at the landing.
const RAMP_MAX_ANGLE_DEG := 38.0
const RAMP_THICKNESS := 0.1
## A little past FLIGHT_WIDTH's own range (0.798 to 0.84 — see
## _build_flight's step_width) so a step brick's painted edge is never
## exactly flush with the collision's own edge, without being so wide it
## swallows the gap between the two ramps (see top-of-file doc comment).
const RAMP_WIDTH := 1.0
## Extra length the low end keeps going past where the slope would
## naturally reach true ground, extended straight on along the same slope
## rather than stopping there — buries that end below the floor instead of
## leaving an exposed edge for a walking player to catch on. Without this a
## player crossing from the flat arena floor onto the ramp meets a small
## lip at the seam and has to jump onto it instead of just walking up.
const RAMP_GROUND_OVERSHOOT := 2.0
## debug_show_ramp_collision colors (see ShopStructure's own export doc
## comment) — one per flight, so the seam between them (and the gap once
## they've pulled apart) reads clearly instead of one solid blob.
const DEBUG_COLOR_L := Color(1.0, 0.15, 0.15, 0.55)
const DEBUG_COLOR_R := Color(0.15, 0.45, 1.0, 0.55)

## A unit box's 8 corners as ±1 sign combinations (multiply by size * 0.5
## and transform to place them) and the 12 edges connecting corners that
## differ in exactly one sign — used by _clip_box_below_y to reconstruct a
## box's geometry without a Mesh/Shape3D already existing to query it.
const _BOX_CORNER_SIGNS := [
	Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1),
	Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(-1, 1, 1), Vector3(1, 1, 1),
]
const _BOX_EDGES := [
	[0, 1], [0, 2], [0, 4], [1, 3], [1, 5], [2, 3],
	[2, 6], [3, 7], [4, 5], [4, 6], [5, 7], [6, 7],
]


## `parent` is the ShopStructure node itself — stairs are added as its
## direct children ("EntranceN"), matching every other generated piece, so
## ShopStructure's own _clear_prefixed(self, "Entrance") can find them again
## on rebuild.
static func build(
	parent: Node3D,
	index: int,
	bay_angle_value: float,
	floor_y: float,
	radius: float,
	sides: int,
	pier_size: Vector2,
	## Tuning knobs for _build_ramp only (see its own doc comment for each
	## key) — bundled into one Dictionary rather than four more positional
	## args to stay clear of gdlint's argument-count cap. Missing keys fall
	## back to this file's own defaults, so passing {} (or omitting this
	## entirely) reproduces the original fixed tuning.
	ramp_config: Dictionary = {}
) -> void:
	if floor_y <= STEP_THICKNESS:
		return
	var chord := 2.0 * radius * sin(deg_to_rad(180.0 / float(sides)))
	var bay_width := maxf(chord - pier_size.x, 0.4)
	## Matches the glazed doors' own width (see ShopStructure._add_bay's
	## identical bay_width * 0.94), so the landing spans the full doorway
	## instead of just part of it.
	var landing_width := bay_width * 0.94
	var landing_half_width := landing_width * 0.5

	var root := Node3D.new()
	root.name = "Entrance%d" % index
	parent.add_child(root)
	root.transform = _ring_transform(bay_angle_value, 0.0, 0.0)

	var landing_dist := radius + LANDING_DEPTH * 0.5
	var landing_y := floor_y - STEP_THICKNESS * 0.5
	_add_slab(
		root, "Landing", Vector3(0.0, landing_y, landing_dist), landing_width, LANDING_DEPTH,
		STONE_TRIM_LOW, STONE_TRIM_HIGH, float(index) * 331.0, true
	)

	var step_count := int(ceil(floor_y / STEP_RISE))
	var outer_dist := radius + LANDING_DEPTH
	## Same slope _build_ramp itself uses (falls back to the same
	## RAMP_MAX_ANGLE_DEG default) — see STEP_RISE's own doc comment for why
	## the steps borrow this rather than keeping a fixed run of their own.
	var ramp_angle_deg: float = ramp_config.get("angle_deg", RAMP_MAX_ANGLE_DEG)
	var step_run := STEP_RISE / tan(deg_to_rad(ramp_angle_deg))
	for side_sign in [-1.0, 1.0]:
		_build_flight(
			root, side_sign, step_count, floor_y, outer_dist, landing_half_width, step_run, index
		)
		_build_ramp(root, side_sign, floor_y, outer_dist, landing_half_width, ramp_config)


## One mirrored flight of a double staircase — side_sign -1/1 picks left or
## right of the shared center axis the landing sits on. A flight starts
## landing_half_width to its own side of that axis (flush with the
## landing's own edge, instead of dead center beneath it) and drifts
## further outward from there, up to landing_half_width +
## FLIGHT_LATERAL_SPREAD by the ground (see lateral below).
static func _build_flight(
	root: Node3D,
	side_sign: float,
	step_count: int,
	floor_y: float,
	outer_dist: float,
	landing_half_width: float,
	step_run: float,
	index: int
) -> void:
	var flight_tag := "L" if side_sign < 0.0 else "R"
	for i in step_count:
		var step_number := i + 1
		var t := float(step_number) / float(step_count)
		var step_y := maxf(floor_y - STEP_RISE * step_number, STEP_THICKNESS * 0.5)
		if step_number == step_count:
			step_y -= LAST_STEP_SINK
		var step_dist := outer_dist + step_run * step_number
		var lateral := side_sign * (landing_half_width + FLIGHT_LATERAL_SPREAD * t)
		var step_width := FLIGHT_WIDTH * (3.0 - 0.15 * t)
		var seed_value := float(index) * 331.0 + side_sign * 97.0 + float(step_number) * 17.0
		_add_slab(
			root, "Step%s%d" % [flight_tag, step_number], Vector3(lateral, step_y, step_dist),
			step_width, FLIGHT_DEPTH, STONE_LOW, STONE_HIGH, seed_value, false
		)


## One rectangular stone slab (a step or the landing) as a StaticBody3D under
## `root`, colored by a per-slab shade jittered within [shade_low, shade_high]
## the same way ShopStructure._add_shop_display picks its own shaft color.
## `collide` is false for steps (see _build_ramp — a shared ramp collision
## stands in for all of them) and true for the landing, the one flat surface
## a player actually stands and lingers on.
static func _add_slab(
	root: Node3D,
	slab_name: String,
	local_position: Vector3,
	width: float,
	depth: float,
	shade_low: float,
	shade_high: float,
	seed_value: float,
	collide: bool
) -> void:
	var body := StaticBody3D.new()
	body.name = slab_name
	body.collision_layer = CollisionLayersScript.WORLD
	body.collision_mask = 0
	root.add_child(body)
	body.position = local_position

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Slab"
	var box := BoxMesh.new()
	box.size = Vector3(width, STEP_THICKNESS, depth)
	mesh_instance.mesh = box
	var hashed := _hash01(seed_value * 3.7)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _stone_color(lerpf(shade_low, shade_high, hashed))
	mat.roughness = 0.85
	mat.metallic = 0.0
	mesh_instance.material_override = mat
	body.add_child(mesh_instance)

	if not collide:
		return
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = box.size
	collision.shape = shape
	body.add_child(collision)


## debug_show_ramp_collision only (see ShopStructure's export doc comment):
## a translucent mesh exactly matching a collision shape's own geometry,
## added as a plain sibling mesh under the same body so it renders in the
## same space the CollisionShape3D beside it occupies — lets a developer
## see the invisible ramp's real extent (the gap between the two flights'
## ramps, and anything top_cut_margin has sliced off) instead of having to
## trust the collision math. `mesh` is the caller's: a BoxMesh sized to
## match for the common uncut case, or a clipped shape's own
## get_debug_mesh() when _clip_box_below_y had to reshape it.
static func _add_debug_mesh(body: Node3D, mesh: Mesh, color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "DebugMesh"
	mesh_instance.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.material_override = mat
	body.add_child(mesh_instance)


## Clips a box (given by its own transform and full size, in `xform`'s
## parent space) against the horizontal plane y == cut_y, keeping only the
## part at or below it — the part of _build_ramp's own doc comment about
## top_cut_margin. ConvexPolygonShape3D builds its own convex hull from an
## unordered point cloud, so the result only needs every kept corner plus
## one new point per edge the cut plane crosses — no face/winding data.
static func _clip_box_below_y(
	xform: Transform3D, size: Vector3, cut_y: float
) -> PackedVector3Array:
	var corners := PackedVector3Array()
	for signs in _BOX_CORNER_SIGNS:
		corners.append(xform * (signs * size * 0.5))
	var points := PackedVector3Array()
	for corner in corners:
		if corner.y <= cut_y:
			points.append(corner)
	for edge in _BOX_EDGES:
		var a: Vector3 = corners[edge[0]]
		var b: Vector3 = corners[edge[1]]
		if (a.y <= cut_y) == (b.y <= cut_y):
			continue
		points.append(a.lerp(b, (cut_y - a.y) / (b.y - a.y)))
	return points


## One straight sloped box, invisible, running the length of one flight at
## `angle_deg` — shallower than the steps' own 45° (see top-of-file doc
## comment) so it always reads as walkable floor — from the landing's outer
## edge down to below true ground. Its top sits landing_half_width to this
## flight's side (matching the flight's own start at the landing's edge)
## and its bottom drifts `tilt` further to that same side, so the ramp is
## tilted sideways as well as sloped; passing `tilt` == FLIGHT_LATERAL_SPREAD
## (ShopStructure's own default for ramp_tilt) matches the flight's own
## straight-line drift exactly, so the ramp follows the same line the
## flight's steps do — pull it away from that to make the ramp visibly
## diverge from the steps under it. Because the ramp's own line is always
## straight regardless of `tilt`, one rigid box follows it exactly with no
## seams along its length for a walking player to catch on.
##
## _segment_transform picks the box's cross-section (its width/thickness
## axes) by keeping "up" as close to world-up as it can — the only free
## choice left once the box's length axis is pinned to the from/top line —
## which is *a* valid orientation but not necessarily one where the two
## mirrored ramps' cross-sections line up with each other: seen edge-on,
## each can end up rolled (rotated around its own length axis) a little
## differently, reading as a twist between them rather than a flush,
## coplanar pair. "roll_deg" corrects that after the fact, applied as
## side_sign * roll_deg so one slider rolls both ramps the same amount in
## mirrored (not identical) directions, keeping the pair symmetric.
##
## `ramp_config` keys (see ShopStructure's matching @export for each,
## which is where a real shop tunes these — this file only supplies the
## fallback defaults a caller who doesn't care can omit):
## - "tilt": float, lateral drift from center to ground (default
##   FLIGHT_LATERAL_SPREAD).
## - "angle_deg": float, slope angle (default RAMP_MAX_ANGLE_DEG).
## - "width": float, collision width (default RAMP_WIDTH).
## - "ground_overshoot": float, low-end burial past true ground (default
##   RAMP_GROUND_OVERSHOOT).
## - "roll_deg": float, post-hoc roll correction, mirrored per side
##   (default 0.0).
## - "top_trim": float, shortens the landing-side end (default 0.0) — see
##   ShopRampTuning.top_trim's own doc comment.
## - "top_cut_margin": float, flat horizontal cut below floor_y (default
##   0.0) — see ShopRampTuning.top_cut_margin's own doc comment.
## - "debug_visible": bool, draw the debug mesh (default false).
static func _build_ramp(
	root: Node3D,
	side_sign: float,
	floor_y: float,
	outer_dist: float,
	landing_half_width: float,
	ramp_config: Dictionary
) -> void:
	var tilt: float = ramp_config.get("tilt", FLIGHT_LATERAL_SPREAD)
	var angle_deg: float = ramp_config.get("angle_deg", RAMP_MAX_ANGLE_DEG)
	var width: float = ramp_config.get("width", RAMP_WIDTH)
	var ground_overshoot: float = ramp_config.get("ground_overshoot", RAMP_GROUND_OVERSHOOT)
	var roll_deg: float = ramp_config.get("roll_deg", 0.0)
	var top_trim: float = ramp_config.get("top_trim", 0.0)
	var top_cut_margin: float = ramp_config.get("top_cut_margin", 0.0)
	var debug_visible: bool = ramp_config.get("debug_visible", false)

	var top := Vector3(side_sign * landing_half_width, floor_y, outer_dist)
	var run := floor_y / tan(deg_to_rad(angle_deg))
	var ground := Vector3(side_sign * (landing_half_width + tilt), 0.0, outer_dist + run)
	var slope_dir := (ground - top).normalized()
	## Pull the landing-side end back down along the slope instead of
	## letting it reach all the way to the landing's outer edge.
	top += slope_dir * minf(top_trim, top.distance_to(ground))
	## Extend past `ground` along the same line instead of stopping there,
	## so the true-ground crossing sits inside the ramp's own length rather
	## than at its very tip.
	var from := ground + slope_dir * ground_overshoot
	var length := from.distance_to(top)
	if length < 0.001:
		return

	var body := StaticBody3D.new()
	body.name = "RampL" if side_sign < 0.0 else "RampR"
	body.collision_layer = CollisionLayersScript.WORLD
	body.collision_mask = 0
	root.add_child(body)
	var xform := _segment_transform(from, top)
	xform.basis = xform.basis.rotated(xform.basis.z.normalized(), deg_to_rad(side_sign * roll_deg))

	var box_size := Vector3(width, RAMP_THICKNESS, length)
	var cut_y := floor_y - top_cut_margin
	var highest_y := -INF
	var lowest_y := INF
	for signs in _BOX_CORNER_SIGNS:
		var corner_y: float = (xform * (signs * box_size * 0.5)).y
		highest_y = maxf(highest_y, corner_y)
		lowest_y = minf(lowest_y, corner_y)

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var debug_mesh: Mesh
	if highest_y <= cut_y:
		## Nothing pokes above the cut — the plain box already fits.
		body.transform = xform
		var shape := BoxShape3D.new()
		shape.size = box_size
		collision.shape = shape
		var box_mesh := BoxMesh.new()
		box_mesh.size = box_size
		debug_mesh = box_mesh
	elif lowest_y > cut_y:
		## The whole box sits above the cut — nothing left to stand on.
		body.free()
		return
	else:
		## body stays at the identity transform its own StaticBody3D
		## default is: _clip_box_below_y already expresses its points in
		## root's (this StaticBody3D's parent's) space, same space `xform`
		## itself is in, so the shape doesn't need a transform on top.
		var shape := ConvexPolygonShape3D.new()
		shape.points = _clip_box_below_y(xform, box_size, cut_y)
		collision.shape = shape
		debug_mesh = shape.get_debug_mesh()
	body.add_child(collision)

	if debug_visible:
		var debug_color := DEBUG_COLOR_L if side_sign < 0.0 else DEBUG_COLOR_R
		_add_debug_mesh(body, debug_mesh, debug_color)


static func _segment_transform(from: Vector3, to: Vector3) -> Transform3D:
	var mid := (from + to) * 0.5
	var dir := to - from
	if dir.length() < 0.0001:
		return Transform3D(Basis(), mid)
	return Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), mid)


static func _ring_transform(angle_deg_value: float, r: float, y: float) -> Transform3D:
	var rad := deg_to_rad(angle_deg_value)
	var basis := Basis(Vector3.UP, rad)
	var pos := Vector3(r * sin(rad), y, r * cos(rad))
	return Transform3D(basis, pos)


## Grey-dominant lightness tint for quarried stone, a duplicate of
## ShopStructure._stone_color (not shared via preload, to avoid a circular
## preload back to shop_structure.gd).
static func _stone_color(value: float) -> Color:
	return Color(value * 0.97, value, value * 1.04)


## Deterministic pseudo-random value in [0, 1) for a given seed — a
## duplicate of ShopStructure._hash01, for the same reason as above.
static func _hash01(n: float) -> float:
	return absf(fmod(sin(n * 12.9898 + 78.233) * 43758.5453, 1.0))
