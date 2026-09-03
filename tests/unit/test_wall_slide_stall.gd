class_name TestWallSlideStall
extends RefCounted

## A body knocked into a convex wall must keep falling, not hang in the air.

const SlideSurfaceScript := preload("res://scripts/slide_surface.gd")
const CollisionLayersScript := preload("res://scripts/collision_layers.gd")

const CAPSULE_RADIUS := 0.2368164
const CAPSULE_HEIGHT := 0.72
const TICKS := 70
const TICK_DELTA := 1.0 / 60.0
const GRAVITY := 9.8
const WALL_INNER_Z := 19.0
const START := Vector3(-12.09, 0.94, 18.73)
const INTO_WALL_SPEED := 23.6
const MIN_VERTICAL_TRAVEL := 1.0


func run() -> int:
	return _test_pressed_into_wall_keeps_moving()


func _test_pressed_into_wall_keeps_moving() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("Expected a SceneTree for wall-slide physics")
		return 1
	var world := Node3D.new()
	tree.root.add_child(world)
	_add_static_box(world, Vector3(52, 1, 38), Vector3(0, -0.5, 0))
	_add_static_box(world, Vector3(56, 24, 2), Vector3(0, 12, WALL_INNER_Z + 1.0))

	var body := _make_body()
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


func _make_body() -> CharacterBody3D:
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = CAPSULE_RADIUS
	capsule.height = CAPSULE_HEIGHT
	shape.shape = capsule
	body.add_child(shape)
	body.collision_layer = CollisionLayersScript.CHARACTER
	body.collision_mask = CollisionLayersScript.CHARACTER_AND_WORLD
	## Engine default (true). The mid-air wall hang was a MOTION_MODE_FLOATING bug;
	## GROUNDED resolves it with floor_block_on_wall left alone. See AGENTS.md.
	body.safe_margin = 0.04
	body.floor_snap_length = 0.0
	body.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	return body


func _add_static_box(parent: Node, size: Vector3, pos: Vector3) -> void:
	var static_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	static_body.add_child(shape)
	static_body.collision_layer = CollisionLayersScript.WORLD
	parent.add_child(static_body)
	static_body.global_position = pos
