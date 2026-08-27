class_name TestWallSlideStall
extends RefCounted

## A body knocked into a wall must keep falling, not hang in the air.
##
## Regression guard for the mid-air stall. In MOTION_MODE_FLOATING,
## move_and_slide discards the entire motion vector -- vertical included -- when
## the body is pressed into a wall at speed, and leaves the into-wall velocity
## untouched. A wizard fireballed into the pit wall froze for 67 of 70 ticks at
## 23.6 m/s, identically on both peers (it is physics, not netcode).
## SlideSurface.sync_motion_from_pose must keep airborne bodies GROUNDED.

const SlideSurfaceScript := preload("res://scripts/slide_surface.gd")

const CAPSULE_RADIUS := 0.2368164
const CAPSULE_HEIGHT := 0.72
const TICKS := 70
const TICK_DELTA := 1.0 / 60.0
const GRAVITY := 9.8
## Wall inner face sits at z = 19; rest the capsule against it.
const WALL_INNER_Z := 19.0
const START := Vector3(-12.09, 0.94, 18.73)
## The stall reproduces above ~10 m/s into the wall; test well past that.
const INTO_WALL_SPEED := 23.6
## Airborne, pressed into a wall, the body must still travel vertically.
const MIN_VERTICAL_TRAVEL := 1.0


func run() -> int:
	var failures := 0
	failures += _test_airborne_mode_is_grounded()
	failures += _test_no_source_selects_floating()
	failures += _test_pressed_into_wall_keeps_moving()
	return failures


## The direct contract: airborne must not select FLOATING.
func _test_airborne_mode_is_grounded() -> int:
	var failures := 0
	for entry in [
		["sync_motion_from_pose", func(b: CharacterBody3D) -> void:
			SlideSurfaceScript.sync_motion_from_pose(b)],
		["prepare", func(b: CharacterBody3D) -> void: SlideSurfaceScript.prepare(b)],
	]:
		var body := _make_body(CharacterBody3D.MOTION_MODE_FLOATING)
		## No world, so has_floor_below() is false -> treated as airborne.
		(entry[1] as Callable).call(body)
		var mode := body.motion_mode
		body.free()
		if mode == CharacterBody3D.MOTION_MODE_FLOATING:
			push_error(
				(
					"%s left the body in MOTION_MODE_FLOATING; move_and_slide "
					+ "drops all motion when pressed into a wall (mid-air stall)."
				)
				% entry[0]
			)
			failures += 1
	return failures


## No player or NPC may ever enter FLOATING. Nothing outside this test file may
## even name the constant -- that is the cheapest way to keep the rule true.
func _test_no_source_selects_floating() -> int:
	var failures := 0
	for path in [
		"res://scripts/slide_surface.gd",
		"res://scripts/characters/playable_character.gd",
		"res://scripts/characters/player_stun.gd",
		"res://scripts/characters/player_crouch.gd",
		"res://scripts/characters/player_dash.gd",
		"res://scripts/characters/player_air_control.gd",
		"res://scripts/monsters/monster.gd",
		"res://scripts/monsters/monster_ai.gd",
		"res://scripts/monsters/charger.gd",
	]:
		var source := FileAccess.get_file_as_string(path)
		if source.is_empty():
			continue
		for line in source.split("\n"):
			var text := str(line).strip_edges()
			if text.begins_with("#") or not text.contains("MOTION_MODE_FLOATING"):
				continue
			push_error(
				"%s selects MOTION_MODE_FLOATING; characters must stay GROUNDED."
				% path
			)
			failures += 1
			break
	return failures


## End to end: the same scenario the capture recorded, in a scratch world.
func _test_pressed_into_wall_keeps_moving() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return 0
	var world := Node3D.new()
	tree.root.add_child(world)
	_add_static_box(world, Vector3(52, 1, 38), Vector3(0, -0.5, 0))
	_add_static_box(world, Vector3(56, 24, 2), Vector3(0, 12, WALL_INNER_Z + 1.0))

	var body := _make_body(CharacterBody3D.MOTION_MODE_GROUNDED)
	world.add_child(body)
	body.global_position = START
	body.velocity = Vector3(0.0, 4.35, INTO_WALL_SPEED)

	var min_y := START.y
	var max_y := START.y
	for _i in TICKS:
		SlideSurfaceScript.sync_motion_from_pose(body)
		body.velocity.y -= GRAVITY * TICK_DELTA
		body.move_and_slide()
		min_y = minf(min_y, body.global_position.y)
		max_y = maxf(max_y, body.global_position.y)

	var travel := max_y - min_y
	world.queue_free()

	if travel < MIN_VERTICAL_TRAVEL:
		push_error(
			"Body pressed into a wall only moved %.2f m vertically over %d ticks — it is stalled mid-air."
			% [travel, TICKS]
		)
		return 1
	return 0


func _make_body(mode: int) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = CAPSULE_RADIUS
	capsule.height = CAPSULE_HEIGHT
	shape.shape = capsule
	body.add_child(shape)
	body.collision_layer = 1
	body.collision_mask = 1
	body.floor_block_on_wall = false
	body.safe_margin = 0.04
	body.floor_snap_length = 0.0
	body.motion_mode = mode
	return body


func _add_static_box(parent: Node, size: Vector3, pos: Vector3) -> void:
	var static_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	static_body.add_child(shape)
	parent.add_child(static_body)
	static_body.global_position = pos
