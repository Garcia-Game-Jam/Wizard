class_name ShopIvyBuilder
extends RefCounted

## Grows ivy as connected vine chains and appends each leaf's transform +
## color into a shared `ivy_batch` Dictionary ({"transforms": [], "colors":
## []}) instead of creating any nodes — ShopStructure._build_ivy_multimesh
## turns the whole batch into a single MultiMeshInstance3D once every
## face/corner/pier has finished growing ivy into it, so however many
## thousand leaves a structure ends up with, it's still one mesh, one
## material, one draw call. Split out of shop_structure.gd only because
## that file hit gdlint's per-file line cap — otherwise as tightly coupled
## to it as if this were still inline (every call is keyed into the
## caller's own index/hash space via _hash01, and every input below —
## `anchor`, `coverage`, `leaf_size_ref` — is a decision ShopStructure's
## callers make, documented on add_face).

const IVY_LOW := 0.16
const IVY_HIGH := 0.42


## Grows ivy as a handful of connected vines up the outer face of a
## foundation wall, corner wedge, or pier — never scattered independent
## clusters. Each vine is a chain of leaf nodes starting at the true base
## (v=0, always placed, never skipped) and stepping upward with only a
## small horizontal wander per step, so consecutive nodes always overlap —
## nothing ends up floating with bare stone underneath it. Vine 0 is always
## rooted dead-center (u=0): a corner wedge below a pier reaches its own
## top there (see force_full_climb) at the exact same point the pier's own
## vine 0 starts climbing from, so a pier's ivy is always physically
## connected down into the base's ivy, not just visually close.
##
## `coverage` (0-1) is this call's own density knob — callers decide what
## drives it. Foundation faces/corners pass the exported ivy_coverage
## directly, so the Inspector slider visibly thickens or thins the base;
## piers instead pass a fixed PIER_IVY_COVERAGE (only gated on/off by
## whether ivy_coverage is >0 at all) so the slider's exact value never
## changes how a pier looks. Vine count scales smoothly with it (a
## fractional remainder still has a chance at one more vine, so density
## isn't quantized into big visible jumps), and can drop to zero on an
## individual face at low coverage — except full_climb_chance callers,
## which always keep at least their center spine (see below).
##
## `leaf_size_ref` sets both leaf size and vertical step spacing, and
## divides into `width` to estimate vine_count — deliberately a caller-
## supplied value, not derived from top_y in here. Foundation
## faces/corners pass their actual brick course height, which is what it
## looks like; piers pass a fixed value instead because pier top_y is the
## pier's own height — a tall, narrow pier would otherwise divide width by
## a huge "course height" and round its vine count down to zero. Real ivy
## doesn't get bigger just because a level designer drags foundation_riser
## or wall_height up, so keeping this off top_y entirely is what keeps
## coverage looking right (and present at all) regardless of a face's
## proportions.
##
## `density_multiplier` lets a caller (the narrower corner wedges) scale
## vine count down further without a separate code path.
##
## `full_climb_chance` is the odds (per vine, 0 disables it) that a vine
## ignores the usual partial-climb range and covers the whole height
## instead — piers pass a partial chance so a vine occasionally makes it
## all the way up one. Passing exactly 1.0 (guaranteed) also pins
## vine_count to at least 1 regardless of coverage — corner wedges pass
## 1.0 so there's always ivy waiting at the top for the pier above to
## connect to, even when the base is otherwise sparse. (Folded into one
## parameter, rather than a separate force-full-climb flag, to stay under
## gdlint's 10-argument function limit.)
static func add_face(
	anchor: Transform3D,
	index: int,
	width: float,
	depth: float,
	top_y: float,
	ivy_batch: Dictionary,
	coverage: float,
	leaf_size_ref: float,
	density_multiplier: float = 1.0,
	full_climb_chance: float = 0.0
) -> void:
	if coverage <= 0.0:
		return
	## Per-face variety — some walls end up more overgrown than others.
	var face_density := coverage * lerpf(0.5, 1.0, _hash01(float(index) * 19.3 + 4.0))
	var course_height := leaf_size_ref
	var outer_z := depth * 0.5 + 0.02
	var expected_vines := (
		width / maxf(course_height, 0.05) * 0.55 * face_density * density_multiplier
	)
	var vine_count := int(expected_vines)
	if _hash01(float(index) * 83.1 + 11.0) < fposmod(expected_vines, 1.0):
		vine_count += 1
	## Any caller opting into full_climb_chance (piers, corner wedges) wants
	## vine PRESENCE guaranteed — only how high it climbs is the "sometimes"
	## — so it can't get density-rolled away to nothing. Plain faces (which
	## pass 0) are the only ones allowed to end up with zero vines; that's
	## what makes the coverage slider actually thin the base out.
	if full_climb_chance > 0.0:
		vine_count = maxi(vine_count, 1)
	for vine_i in vine_count:
		var vine_seed := float(index * 601 + vine_i * 29 + 3)
		var climb_fraction := lerpf(0.45, 1.0, _hash01(vine_seed * 3.7))
		if full_climb_chance > 0.0 and _hash01(vine_seed * 8.3) < full_climb_chance:
			climb_fraction = 1.0
		var climb_height := climb_fraction * top_y
		var step := course_height * 0.65
		var step_count := maxi(1, int(climb_height / step))
		## vine 0 always roots dead-center — see doc comment above for why.
		var cur_u := 0.0 if vine_i == 0 else lerpf(-0.42, 0.42, _hash01(vine_seed * 1.3)) * width
		var cur_v := 0.0
		for s in step_count + 1:
			if s > 0:
				cur_u += (_hash01(vine_seed * 4.1 + float(s) * 1.9) - 0.5) * course_height * 0.9
				cur_u = clampf(cur_u, -width * 0.47, width * 0.47)
				cur_v = minf(cur_v + step, climb_height)
			var node_seed := vine_seed * 5.3 + float(s) * 17.0
			var base_position := Vector3(cur_u, cur_v, outer_z)
			var leaves_here := 2 + int(_hash01(node_seed * 3.1) * (2.0 + 4.0 * face_density))
			for leaf_idx in leaves_here:
				_add_leaf(
					anchor, base_position, node_seed + float(leaf_idx) * 7.0, course_height, ivy_batch
				)


## Scatters a small, self-contained clump of leaves around `local_position`
## (in `anchor`'s local space) — for ivy that isn't climbing a vertical face
## at all, like the tufts ShopStructure's entrance steps grow at their
## edges. Not part of add_face's vine-chain growth: every leaf here is just
## jittered around one point, so callers that want ivy connected across
## several points (e.g. one clump per step) should call this once per point
## rather than expect any continuity between calls.
static func add_clump(
	anchor: Transform3D,
	local_position: Vector3,
	leaf_count: int,
	spread: float,
	leaf_size_ref: float,
	ivy_batch: Dictionary,
	seed_value: float
) -> void:
	for leaf_idx in leaf_count:
		var leaf_seed := seed_value + float(leaf_idx) * 9.7
		var offset := Vector3(
			(_hash01(leaf_seed * 2.3) - 0.5) * spread,
			(_hash01(leaf_seed * 3.1) - 0.5) * spread * 0.5,
			(_hash01(leaf_seed * 4.7) - 0.5) * spread
		)
		_add_leaf(anchor, local_position + offset, leaf_seed * 5.9, leaf_size_ref, ivy_batch)


## Appends one leaf's transform+color to ivy_batch instead of creating a
## node. `anchor` is the owning face/wedge/pier's transform relative to
## ShopStructure itself, since a leaf's own position/rotation/scale below
## are all still expressed in that face's local space.
static func _add_leaf(
	anchor: Transform3D,
	base_position: Vector3,
	seed_value: float,
	course_height: float,
	ivy_batch: Dictionary
) -> void:
	var shade := lerpf(IVY_LOW, IVY_HIGH, _hash01(seed_value * 5.3))
	var jitter := Vector3(
		(_hash01(seed_value * 1.1) - 0.5) * course_height * 0.7,
		(_hash01(seed_value * 1.9) - 0.5) * course_height * 0.7,
		_hash01(seed_value * 4.1) * 0.04
	)
	var euler_rad := Vector3(
		deg_to_rad((_hash01(seed_value * 6.1) - 0.5) * 50.0),
		deg_to_rad((_hash01(seed_value * 7.3) - 0.5) * 40.0),
		deg_to_rad(_hash01(seed_value * 8.9) * 360.0)
	)
	var leaf_scale := lerpf(0.3, 0.55, _hash01(seed_value * 2.7)) * course_height
	var local_basis := Basis.from_euler(euler_rad).scaled(Vector3.ONE * leaf_scale)
	var local_transform := Transform3D(local_basis, base_position + jitter)
	(ivy_batch["transforms"] as Array).append(anchor * local_transform)
	(ivy_batch["colors"] as Array).append(_ivy_color(shade))


## Green-dominant tint for a lightness value — same idea as
## ShopStructure._stone_color's sibling, just aimed at foliage instead of
## quarried stone.
static func _ivy_color(value: float) -> Color:
	return Color(value * 0.32, value * 0.85, value * 0.22)


## Deterministic pseudo-random value in [0, 1) for a given seed — a
## duplicate of ShopStructure._hash01 (not shared via preload, to avoid a
## circular preload back to shop_structure.gd), so it stays identical
## across rebuilds regardless of which file calls it.
static func _hash01(n: float) -> float:
	return absf(fmod(sin(n * 12.9898 + 78.233) * 43758.5453, 1.0))
