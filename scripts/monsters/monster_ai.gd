class_name MonsterAI
extends RefCounted

## Pure helpers for Monster FSM / targeting / interest preferencing.

enum State { IDLE, PATROL, CHASE, ALERT }
## Lookdev pose → eyes. Chase shows eyes; Patrol hides them.
enum LookdevPose { PATROL, CHASE }

const NetClockScript := preload("res://scripts/net/net_clock.gd")
const CollisionLayersScript := preload("res://scripts/collision_layers.gd")

## A charge capsule this wide (half-width, m) must fit the whole lane for the ram
## to be worth committing — a single centre ray "clear" still clips corners.
const CHARGE_LANE_HALF_W := 0.85


## Safe Node3D from a stored ref. Freed objects are not null — never `as` before this.
static func live_node3d(node: Variant) -> Node3D:
	if not is_instance_valid(node) or not (node is Node3D):
		return null
	return node as Node3D


## Returns index of nearest living target within chase_range, or -1.
static func pick_nearest_target_index(
	origin: Vector3,
	target_positions: Array,
	target_alive: Array,
	chase_range: float
) -> int:
	var best_i := -1
	var best_d2 := chase_range * chase_range
	var n := mini(target_positions.size(), target_alive.size())
	for i in range(n):
		if not bool(target_alive[i]):
			continue
		var pos: Vector3 = target_positions[i]
		var d2 := Vector3(pos.x - origin.x, 0.0, pos.z - origin.z).length_squared()
		if d2 <= best_d2:
			best_d2 = d2
			best_i = i
	return best_i


## Distance-based urgency in (0, 1], nearer = higher. 0 if out of range.
static func proximity_urgency(origin: Vector3, target: Vector3, range_m: float) -> float:
	if range_m <= 0.0:
		return 0.0
	var flat := Vector3(target.x - origin.x, 0.0, target.z - origin.z)
	var dist := flat.length()
	if dist > range_m:
		return 0.0
	return 1.0 - (dist / range_m) * 0.5


## Default preferencing: highest urgency among actionable candidates.
static func prefer_highest_urgency(candidates: Array) -> RefCounted:
	var best: RefCounted = null
	var best_u := 0.0
	for item in candidates:
		if item == null or not item.has_method("is_actionable"):
			continue
		if not bool(item.call("is_actionable")):
			continue
		var urgency := float(item.get("urgency"))
		if best == null or urgency > best_u:
			best = item
			best_u = urgency
	return best


## The arena is a closed pit — a living monster is always hunting. Kept as a
## function (and the State enum kept) so callers/subclasses do not have to change.
static func resolve_state(_current: State, _has_chase_target: bool) -> State:
	return State.CHASE


## Eyes stay on while a monster is hunting (which is always, while alive).
static func chase_eyes_visible(state: State) -> bool:
	return state == State.CHASE or state == State.ALERT


## Composite "chase this one" score for a candidate player. Higher wins.
## proximity dominates; being dead-ahead and being seen (vs heard/remembered)
## add on; the current target gets a stickiness bonus to stop flip-flop.
static func score_player_target(
	from_pos: Vector3,
	facing_flat: Vector3,
	player_pos: Vector3,
	sense_range: float,
	seen: bool,
	is_current: bool
) -> float:
	var flat := Vector3(player_pos.x - from_pos.x, 0.0, player_pos.z - from_pos.z)
	var dist := flat.length()
	var rng := maxf(sense_range, 0.5)
	var score := (1.0 - clampf(dist / rng, 0.0, 1.0)) * 2.0
	if dist > 0.05:
		var fwd := Vector3(facing_flat.x, 0.0, facing_flat.z)
		if fwd.length_squared() > 0.0001:
			score += maxf(0.0, fwd.normalized().dot(flat / dist)) * 0.5
	if seen:
		score += 0.6
	if is_current:
		score += 0.4
	return score


## Where a monster with no target and no memory should advance: the centroid of
## PlayerSpawn* markers under `scene_root`, else `fallback` (arena centre).
static func hunt_seek_goal(scene_root: Node, fallback: Vector3) -> Vector3:
	if scene_root == null:
		return fallback
	var sum := Vector3.ZERO
	var n := 0
	var stack: Array[Node] = [scene_root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Node3D and str(node.name).begins_with("PlayerSpawn"):
			sum += (node as Node3D).global_position
			n += 1
			continue
		for child in node.get_children():
			stack.append(child)
	if n == 0:
		return fallback
	return Vector3(sum.x / float(n), fallback.y, sum.z / float(n))


## Local obstacle steering. Returns a nudged goal that (a) rounds the near edge
## of anything blocking the straight lane and (b) pushes away from nearby walls
## so the monster keeps `clearance_m` of breathing room and takes a wide arc
## around corners instead of hugging them. Cheap and deterministic (static
## geometry raycasts). One detour bounce; returns `goal` when nothing applies.
static func avoid_obstacles(
	world: World3D,
	from: Vector3,
	goal: Vector3,
	self_rid: RID,
	clearance_m: float = 0.0,
	probe_height: float = 0.6,
	lookahead: float = 6.0,
	side_step: float = 1.6
) -> Vector3:
	if world == null or world.direct_space_state == null:
		return goal
	var flat := Vector3(goal.x - from.x, 0.0, goal.z - from.z)
	var dist := flat.length()
	if dist < 0.5:
		return goal
	var dir := flat / dist
	var reach := minf(dist, lookahead)
	var eye := from + Vector3(0.0, probe_height, 0.0)
	var lane_open := not _lane_blocked(world, eye, eye + dir * reach, self_rid)
	if lane_open and clearance_m <= 0.05:
		return goal

	## 1. Round a blocker in the lane — take the near edge on a wide arc, or if
	## both sides are blocked, commit to sliding along the clearer one.
	if not lane_open:
		var right := Vector3(-dir.z, 0.0, dir.x)
		var first := 1.0 if right.dot(flat) >= 0.0 else -1.0
		var found := false
		for s in [first, -first]:
			var blend: Vector3 = dir + right * (s * maxf(side_step, 0.1))
			if blend.length_squared() < 0.0001:
				continue
			var b_dir := blend.normalized()
			if not _lane_blocked(world, eye, eye + b_dir * reach, self_rid):
				dir = b_dir
				found = true
				break
		if not found:
			dir = (right * first + dir * 0.2).normalized()

	## 2. Push off nearby walls (also widens the arc at corners).
	if clearance_m > 0.05:
		var repel := wall_repulsion(world, eye, self_rid, clearance_m)
		if repel.length_squared() > 0.0001:
			var steered: Vector3 = dir + repel
			if steered.length_squared() > 0.0001:
				dir = steered.normalized()

	return from + dir * reach


## Sum of "get away from me" pushes from world surfaces within `clearance` of
## `eye`, each weighted by how close it is. Zero when nothing is near.
static func wall_repulsion(
	world: World3D, eye: Vector3, self_rid: RID, clearance: float
) -> Vector3:
	if world == null or world.direct_space_state == null or clearance <= 0.0:
		return Vector3.ZERO
	var push := Vector3.ZERO
	for i in 8:
		var ang := float(i) * TAU / 8.0
		var probe := Vector3(cos(ang), 0.0, sin(ang))
		var q := PhysicsRayQueryParameters3D.create(eye, eye + probe * clearance)
		q.collide_with_areas = false
		q.collision_mask = CollisionLayersScript.WORLD
		if self_rid.is_valid():
			q.exclude = [self_rid]
		var hit := world.direct_space_state.intersect_ray(q)
		if hit.is_empty():
			continue
		var d := eye.distance_to(hit.get("position"))
		var strength := 1.0 - clampf(d / clearance, 0.0, 1.0)
		var away := Vector3((hit.get("normal") as Vector3).x, 0.0, (hit.get("normal") as Vector3).z)
		if away.length_squared() < 0.01:
			away = -probe
		push += away.normalized() * strength
	return Vector3(push.x, 0.0, push.z)


## True when a corridor `2 * half_w` wide from `a` to `b` is unobstructed.
static func corridor_clear(
	world: World3D, a: Vector3, b: Vector3, half_w: float, self_rid: RID
) -> bool:
	if world == null or world.direct_space_state == null:
		return true
	var span := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if span.length_squared() < 0.01:
		return true
	var perp := Vector3(-span.z, 0.0, span.x).normalized() * maxf(half_w, 0.05)
	for o in [Vector3.ZERO, perp, -perp]:
		if _lane_blocked(world, a + o, b + o, self_rid):
			return false
	return true


## Widest half-width (up to ~2.6x the base) for which the a→b corridor stays
## clear. Higher = a wider, safer angle to charge through.
static func lane_margin(
	world: World3D,
	a: Vector3,
	b: Vector3,
	self_rid: RID,
	base_half_w: float = CHARGE_LANE_HALF_W
) -> float:
	var w0 := maxf(base_half_w, 0.1)
	var best := 0.0
	for w in [w0, w0 * 1.7, w0 * 2.6]:
		if not corridor_clear(world, a, b, w, self_rid):
			break
		best = w
	return best


## Best spot to line up a threatening charge at `player`: `stage_range` out on a
## bearing whose corridor to the player is clear and at least `lane_half_w` wide
## on each side (so it doesn't graze a corner), with run-up room behind and room
## off the walls. Samples a fan biased toward the charger's current side. Returns
## {pos, ok} — ok is false when no bearing gives a wide clean corridor; pos is
## then the widest-margin bearing so the charger keeps sidestepping toward a real
## angle instead of committing.
static func pick_charge_staging(
	world: World3D,
	charger_pos: Vector3,
	player_pos: Vector3,
	stage_range: float,
	lane_half_w: float,
	clearance: float,
	self_rid: RID
) -> Dictionary:
	var radius := maxf(stage_range, 1.0)
	var lane_w := maxf(lane_half_w, 0.1)
	var to_charger := Vector3(charger_pos.x - player_pos.x, 0.0, charger_pos.z - player_pos.z)
	var fallback: Vector3 = player_pos + (
		to_charger.normalized() if to_charger.length_squared() > 0.01 else Vector3.FORWARD
	) * radius
	fallback.y = charger_pos.y
	if world == null or world.direct_space_state == null:
		return {"pos": fallback, "ok": true}
	var base := atan2(to_charger.z, to_charger.x) if to_charger.length_squared() > 0.01 else 0.0
	var up := Vector3(0.0, 0.6, 0.0)
	var pe: Vector3 = player_pos + up
	var best := fallback
	var best_score := -INF
	var best_open := Vector3.ZERO
	var best_open_margin := -1.0
	for off in [0.0, 0.25, -0.25, 0.5, -0.5, 0.8, -0.8, 1.15, -1.15, 1.6, -1.6]:
		var a: float = base + off
		var s: Vector3 = player_pos + Vector3(cos(a), 0.0, sin(a)) * radius
		s.y = charger_pos.y
		var se: Vector3 = s + up
		var margin := lane_margin(world, se, pe, self_rid, lane_w)
		if margin > best_open_margin:
			best_open_margin = margin
			best_open = s
		if margin < lane_w:
			continue  # corridor would clip a wall / corner
		var behind: Vector3 = s + (s - player_pos).normalized() * (radius * 0.3)
		if _lane_blocked(world, se, behind + up, self_rid):
			continue  # no run-up room behind
		if wall_repulsion(world, se, self_rid, clearance).length() > 0.85:
			continue  # jammed against a wall
		var score := margin * 4.0 - charger_pos.distance_to(s) * 0.5 - absf(off) * radius * 0.4
		if score > best_score:
			best_score = score
			best = s
	if best_score == -INF:
		return {"pos": best_open, "ok": false}
	return {"pos": best, "ok": true}


## Guess where a just-lost player went: if cover / a wall is close to their
## last-seen spot, the far side of that edge (circling away from `from`).
## Returns `last_seen` unchanged when nothing is close enough to hide behind.
static func peek_past_cover(
	world: World3D, from: Vector3, last_seen: Vector3, self_rid: RID, peek_dist: float = 3.0
) -> Vector3:
	if world == null or world.direct_space_state == null:
		return last_seen
	var eye := last_seen + Vector3(0.0, 0.6, 0.0)
	var near_dir := Vector3.ZERO
	var near_d := 4.0
	for i in 12:
		var ang := float(i) * TAU / 12.0
		var probe := Vector3(cos(ang), 0.0, sin(ang))
		var q := PhysicsRayQueryParameters3D.create(eye, eye + probe * near_d)
		q.collide_with_areas = false
		q.collision_mask = CollisionLayersScript.WORLD
		if self_rid.is_valid():
			q.exclude = [self_rid]
		var hit := world.direct_space_state.intersect_ray(q)
		if hit.is_empty():
			continue
		var d := eye.distance_to(hit.get("position"))
		if d < near_d:
			near_d = d
			near_dir = probe
	if near_dir.length_squared() < 0.01:
		return last_seen
	var tangent := Vector3(-near_dir.z, 0.0, near_dir.x)
	var to_from := Vector3(from.x - last_seen.x, 0.0, from.z - last_seen.z)
	if tangent.dot(to_from) > 0.0:
		tangent = -tangent  # step to the side away from the charger
	var peek: Vector3 = last_seen + tangent * peek_dist + near_dir * 0.6
	peek.y = last_seen.y
	return peek


static func _lane_blocked(world: World3D, a: Vector3, b: Vector3, self_rid: RID) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.collide_with_areas = false
	q.collision_mask = CollisionLayersScript.WORLD
	if self_rid.is_valid():
		q.exclude = [self_rid]
	return not world.direct_space_state.intersect_ray(q).is_empty()


static func lookdev_eyes_visible(pose: LookdevPose) -> bool:
	return pose == LookdevPose.CHASE


static func random_patrol_point(
	origin: Vector3, radius: float, angle_rad: float, dist_factor: float
) -> Vector3:
	var dist := clampf(dist_factor, 0.0, 1.0) * maxf(0.0, radius)
	return Vector3(
		origin.x + cos(angle_rad) * dist,
		origin.y,
		origin.z + sin(angle_rad) * dist
	)


static func horizontal_velocity_toward(
	from: Vector3, to: Vector3, speed: float, y_velocity: float = 0.0
) -> Vector3:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	if flat.length_squared() < 0.0001:
		return Vector3(0.0, y_velocity, 0.0)
	var dir := flat.normalized()
	return Vector3(dir.x * speed, y_velocity, dir.z * speed)


## Yaw that points local -Z along a flat world direction (Godot forward).
static func yaw_from_flat(desired_flat: Vector3) -> float:
	var flat := Vector3(desired_flat.x, 0.0, desired_flat.z)
	if flat.length_squared() < 0.0001:
		return 0.0
	var dir := flat.normalized()
	return atan2(-dir.x, -dir.z)


## Rotate current yaw toward a flat desired facing vector at speed_rad.
static func rotate_yaw_toward(
	current_yaw: float, desired_flat: Vector3, speed_rad: float, delta: float
) -> float:
	var flat := Vector3(desired_flat.x, 0.0, desired_flat.z)
	if flat.length_squared() < 0.0001:
		return current_yaw
	return rotate_toward(
		current_yaw, yaw_from_flat(flat), maxf(speed_rad, 0.01) * maxf(delta, 0.0)
	)


## Max distance from the player for chase reposition (80% of aggro / chase_range).
static func max_aggro_move_distance(chase_range: float) -> float:
	return maxf(0.0, chase_range) * 0.8


static func pick_chase_wait_sec(
	rng: RandomNumberGenerator, min_sec: float = 1.0, max_sec: float = 3.0
) -> float:
	return rng.randf_range(minf(min_sec, max_sec), maxf(min_sec, max_sec))


static func pick_chase_strafe_sec(
	rng: RandomNumberGenerator, min_sec: float = 1.2, max_sec: float = 2.0
) -> float:
	return rng.randf_range(minf(min_sec, max_sec), maxf(min_sec, max_sec))


static func pick_chase_retreat_sec(
	rng: RandomNumberGenerator, min_sec: float = 1.2, max_sec: float = 3.2
) -> float:
	return rng.randf_range(minf(min_sec, max_sec), maxf(min_sec, max_sec))


static func pick_wretch_post_cast_move_sec(
	rng: RandomNumberGenerator, min_sec: float = 0.5, max_sec: float = 1.5
) -> float:
	return rng.randf_range(minf(min_sec, max_sec), maxf(min_sec, max_sec))


static func horizontal_distance(from: Vector3, to: Vector3) -> float:
	return Vector3(to.x - from.x, 0.0, to.z - from.z).length()


## Flat unit vector from monster toward player. Zero if coincident.
static func toward_player_flat(from: Vector3, player: Vector3) -> Vector3:
	var flat := Vector3(player.x - from.x, 0.0, player.z - from.z)
	if flat.length_squared() < 0.0001:
		return Vector3.ZERO
	return flat.normalized()


## Which lateral sign (+right / -right vs facing the player) increases range.
static func strafe_sign_further_from_player(from: Vector3, player: Vector3) -> float:
	var toward := toward_player_flat(from, player)
	if toward.length_squared() < 0.0001:
		return 1.0
	var right := Vector3(-toward.z, 0.0, toward.x)
	if right.length_squared() < 0.0001:
		return 1.0
	right = right.normalized()
	var step := 0.5
	var d_right := horizontal_distance(from + right * step, player)
	var d_left := horizontal_distance(from - right * step, player)
	return 1.0 if d_right >= d_left else -1.0


## 70:30 default toward the further-from-player strafe sign.
static func pick_weighted_strafe_sign(
	further_sign: float, roll: float, further_weight: float = 0.7
) -> float:
	var away := 1.0 if further_sign >= 0.0 else -1.0
	if roll < clampf(further_weight, 0.0, 1.0):
		return away
	return -away


## Angled strafe: mostly sideways with a small radial blend (positive = toward player).
static func angled_strafe_dir(
	from: Vector3,
	player: Vector3,
	side_sign: float,
	radial_blend: float = 0.28
) -> Vector3:
	var toward := toward_player_flat(from, player)
	if toward.length_squared() < 0.0001:
		return Vector3.ZERO
	var side := Vector3(-toward.z, 0.0, toward.x) * signf(side_sign)
	if side.length_squared() < 0.0001:
		return toward
	var blend := clampf(radial_blend, 0.0, 0.85)
	var dir := (side * (1.0 - blend) + toward * blend).normalized()
	return dir


## Angled retreat: mostly away from player with a lateral bias.
static func angled_retreat_dir(
	from: Vector3,
	player: Vector3,
	side_sign: float,
	lateral_blend: float = 0.38
) -> Vector3:
	var toward := toward_player_flat(from, player)
	if toward.length_squared() < 0.0001:
		return Vector3.ZERO
	var away := -toward
	var side := Vector3(-toward.z, 0.0, toward.x) * signf(side_sign)
	var blend := clampf(lateral_blend, 0.0, 0.85)
	var dir := (away * (1.0 - blend) + side * blend).normalized()
	return dir


static func can_retreat_farther(from: Vector3, player: Vector3, max_dist: float) -> bool:
	return horizontal_distance(from, player) < max_dist - 0.05


## Zero horizontal retreat when already at/over the aggro move cap.
static func retreat_velocity_clamped(
	from: Vector3,
	player: Vector3,
	move_dir: Vector3,
	speed: float,
	y_velocity: float,
	max_dist: float
) -> Vector3:
	if not can_retreat_farther(from, player, max_dist):
		return Vector3(0.0, y_velocity, 0.0)
	var flat_dir := Vector3(move_dir.x, 0.0, move_dir.z)
	if flat_dir.length_squared() < 0.0001:
		return Vector3(0.0, y_velocity, 0.0)
	flat_dir = flat_dir.normalized()
	var step := maxf(speed, 0.0) * 0.05
	var next := from + flat_dir * step
	if horizontal_distance(next, player) > max_dist:
		return Vector3(0.0, y_velocity, 0.0)
	return Vector3(flat_dir.x * speed, y_velocity, flat_dir.z * speed)


## Flat unit vector of where the player is looking (XZ only).
static func player_facing_flat(player: Node3D) -> Vector3:
	if player == null:
		return Vector3(0.0, 0.0, -1.0)
	var head := player.get_node_or_null("Head") as Node3D
	var source: Node3D = head if head != null else player
	var basis: Basis = source.transform.basis
	if source.is_inside_tree():
		basis = source.global_transform.basis
	var forward := Vector3(-basis.z.x, 0.0, -basis.z.z)
	if forward.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, -1.0)
	return forward.normalized()


## Landing spot away from the player along the current radial, clamped to aggro cap.
static func pick_dash_landing_away(
	monster_pos: Vector3,
	player: Node3D,
	distance: float,
	max_dist_from_player: float
) -> Vector3:
	if player == null:
		return monster_pos
	var player_pos := player.global_position
	var away := Vector3(
		monster_pos.x - player_pos.x, 0.0, monster_pos.z - player_pos.z
	)
	if away.length_squared() < 0.0001:
		away = Vector3(0.0, 0.0, 1.0)
	else:
		away = away.normalized()
	var landing := monster_pos + away * maxf(distance, 0.0)
	landing.y = monster_pos.y
	var to_landing := Vector3(landing.x - player_pos.x, 0.0, landing.z - player_pos.z)
	if to_landing.length_squared() > 0.0001 and to_landing.length() > max_dist_from_player:
		landing = player_pos + to_landing.normalized() * max_dist_from_player
		landing.y = monster_pos.y
	return landing


## Dash in along the player radial and stop at `range_m`.
static func pick_dash_landing_at_range(
	monster_pos: Vector3,
	player: Node3D,
	range_m: float,
	max_dist_from_player: float
) -> Vector3:
	if player == null:
		return monster_pos
	var player_pos := player.global_position
	var to_player := Vector3(
		player_pos.x - monster_pos.x, 0.0, player_pos.z - monster_pos.z
	)
	var dist := to_player.length()
	var goal_range := clampf(range_m, 0.4, maxf(max_dist_from_player, range_m))
	if dist <= goal_range + 0.15:
		return monster_pos
	var landing := player_pos - to_player.normalized() * goal_range
	landing.y = monster_pos.y
	return landing


## Sidestep near 90° from `inbound_dir`, preferring the side that stays farther from the player.
static func pick_dash_landing_sidestep(
	monster_pos: Vector3,
	player: Node3D,
	inbound_dir: Vector3,
	distance: float,
	max_dist_from_player: float
) -> Vector3:
	if player == null:
		return monster_pos
	var inbound := Vector3(inbound_dir.x, 0.0, inbound_dir.z)
	if inbound.length_squared() < 0.0001:
		inbound = Vector3(
			monster_pos.x - player.global_position.x,
			0.0,
			monster_pos.z - player.global_position.z
		)
	if inbound.length_squared() < 0.0001:
		inbound = Vector3(1.0, 0.0, 0.0)
	else:
		inbound = inbound.normalized()
	var right := Vector3(-inbound.z, 0.0, inbound.x)
	var away := Vector3(
		monster_pos.x - player.global_position.x,
		0.0,
		monster_pos.z - player.global_position.z
	)
	var side := right
	var away_dot := right.dot(away)
	if away_dot < -0.05:
		side = -right
	elif absf(away_dot) <= 0.05:
		side = right if inbound.x >= 0.0 else -right
	return _clamp_landing(
		monster_pos + side * maxf(distance, 0.0), monster_pos, player, max_dist_from_player
	)


static func _clamp_landing(
	landing: Vector3, monster_pos: Vector3, player: Node3D, max_dist_from_player: float
) -> Vector3:
	landing.y = monster_pos.y
	if player == null:
		return landing
	var player_pos := player.global_position
	var to_landing := Vector3(landing.x - player_pos.x, 0.0, landing.z - player_pos.z)
	if to_landing.length_squared() > 0.0001 and to_landing.length() > max_dist_from_player:
		landing = player_pos + to_landing.normalized() * max_dist_from_player
		landing.y = monster_pos.y
	return landing


## Landing spot behind the player's view at preferred range, biased to the monster's side.
static func pick_dash_landing_behind(
	monster_pos: Vector3,
	player: Node3D,
	preferred_range: float,
	max_dist_from_player: float
) -> Vector3:
	if player == null:
		return monster_pos
	var player_pos := player.global_position
	var forward := player_facing_flat(player)
	var behind := -forward
	var lateral := Vector3(-forward.z, 0.0, forward.x)
	var to_monster := Vector3(
		monster_pos.x - player_pos.x, 0.0, monster_pos.z - player_pos.z
	)
	var side_sign := signf(lateral.dot(to_monster))
	if absf(side_sign) < 0.01:
		side_sign = 1.0
	var dist := clampf(preferred_range * 0.95, 1.0, max_dist_from_player)
	var landing := player_pos + behind * dist + lateral * side_sign * 0.5
	landing.y = monster_pos.y
	var to_landing := Vector3(landing.x - player_pos.x, 0.0, landing.z - player_pos.z)
	if to_landing.dot(forward) > 0.0:
		landing = player_pos + behind * dist + lateral * side_sign * 0.5
		to_landing = Vector3(landing.x - player_pos.x, 0.0, landing.z - player_pos.z)
	if to_landing.length_squared() > 0.0001 and to_landing.length() > max_dist_from_player:
		landing = player_pos + to_landing.normalized() * max_dist_from_player
		landing.y = monster_pos.y
	return landing


static func is_lookdev_live(node: Node) -> bool:
	return Engine.is_editor_hint() and node != null and bool(node.get_meta("lookdev_live_ai", false))


static func apply_gravity(body: CharacterBody3D, delta: float, gravity: float) -> void:
	## Lookdev editor has no reliable floor contact — hold Y so LOS stays valid.
	## Do not zero a positive Y on the floor: that ate stone knock-up in solo.
	if body == null:
		return
	var v := body.velocity
	if is_lookdev_live(body):
		v.y = 0.0
	elif body.is_on_floor() and v.y <= 0.05:
		v.y = 0.0
	else:
		v.y -= gravity * delta
	body.velocity = v


static func apply_move(body: CharacterBody3D, delta: float) -> void:
	if body == null:
		return
	if is_lookdev_live(body):
		body.velocity.y = 0.0
		var before := body.global_position
		NetClockScript.move_character(body)
		var moved := Vector3(
			body.global_position.x - before.x, 0.0, body.global_position.z - before.z
		)
		if moved.length() < 0.0001:
			_lookdev_translate(body, delta)
		return
	NetClockScript.move_character(body)


static func _lookdev_translate(body: CharacterBody3D, delta: float) -> void:
	var step := Vector3(body.velocity.x, 0.0, body.velocity.z) * delta
	if step.length() < 0.0001:
		return
	var dest := body.global_position + step
	body.global_position = Vector3(dest.x, body.global_position.y, dest.z)
