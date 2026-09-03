class_name TestChargerWallStun
extends RefCounted

## A ram that hits a wall must resolve to WALL_STUN — not stay pinned in CHARGE.
## The old bug: _try_ram_contacts read get_slide_collision() after NetClock's
## substepped move_and_slide loop, so a grounded head-on ram registered the wall
## only when contact landed on the final substep, and once parked, never.
## A ram that hits nothing must skid to RECOVER, never charge forever.
##
## Runs on real engine physics frames (move_and_slide only advances a body a
## realistic distance from inside a physics step), far from the origin so leftover
## bodies from earlier suites — which share this World3D — cannot touch it.

const ChargerScene := preload("res://scenes/monsters/charger.tscn")
const CollisionLayersScript := preload("res://scripts/collision_layers.gd")
## Charger.ChargePhase: NONE, TELEGRAPH, CHARGE, WALL_STUN, SEARCH, STALK, RECOVER, FEINT
const CHARGE := 2
const WALL_STUN := 3
const SEARCH := 4
const RECOVER := 6
const ORIGIN := Vector3(2000.0, 0.0, 0.0)


func run(tree: SceneTree) -> int:
	var failures := 0
	failures += await _test_grounded_ram_into_wall_reaches_wall_stun(tree)
	failures += await _test_open_ram_recovers_and_never_loops(tree)
	return failures


func _add_box(parent: Node, size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.collision_layer = CollisionLayersScript.WORLD
	body.collision_mask = 0
	parent.add_child(body)
	body.global_position = pos


## Isolate the ram: no telegraph, no held ward, and no senses.
func _spawn_charging(tree: SceneTree, world: Node3D) -> Charger:
	var charger := ChargerScene.instantiate() as Charger
	world.add_child(charger)
	var senses := charger.get_node_or_null("Senses")
	if senses != null:
		for sense in senses.get_children():
			if "enabled" in sense:
				sense.set("enabled", false)
	charger.global_position = ORIGIN + Vector3(0.0, 0.36, 0.0)
	charger.rotation = Vector3(0.0, -PI / 2.0, 0.0)  # face +X
	charger.set_physics_process(true)
	for _i in 12:
		await tree.physics_frame  # settle onto the floor
	charger.rotation = Vector3(0.0, -PI / 2.0, 0.0)
	charger.call("_begin_charging")
	charger.call("_shatter_ward")
	charger.set("_charge_target", null)
	return charger


func _charge_until_resolved(tree: SceneTree, charger: Charger, max_frames: int) -> int:
	for _i in max_frames:
		await tree.physics_frame
		if int(charger.get("_phase")) != CHARGE:
			return int(charger.get("_phase"))
	return CHARGE


func _test_grounded_ram_into_wall_reaches_wall_stun(tree: SceneTree) -> int:
	var world := Node3D.new()
	tree.root.add_child(world)
	_add_box(world, Vector3(60, 1, 60), ORIGIN + Vector3(0, -0.5, 0))
	_add_box(world, Vector3(2, 8, 40), ORIGIN + Vector3(4.0, 4, 0))  # wall 4 m ahead

	var charger := await _spawn_charging(tree, world)
	var phase := await _charge_until_resolved(tree, charger, 240)
	var dx := charger.global_position.x - ORIGIN.x
	world.queue_free()
	await tree.process_frame

	if phase == CHARGE:
		push_error("charger stayed in CHARGE ramming a wall (dx=%.2f) — the stuck bug" % dx)
		return 1
	if phase != WALL_STUN:
		push_error("ram into a wall resolved to phase %d, expected WALL_STUN" % phase)
		return 1
	if dx > 5.0:
		push_error("charger tunnelled past the wall to dx=%.2f before wall-stunning" % dx)
		return 1
	return 0


func _test_open_ram_recovers_and_never_loops(tree: SceneTree) -> int:
	var world := Node3D.new()
	tree.root.add_child(world)
	_add_box(world, Vector3(400, 1, 400), ORIGIN + Vector3(0, -0.5, 0))  # floor only

	var charger := await _spawn_charging(tree, world)
	var phase := await _charge_until_resolved(tree, charger, 240)
	var dx := charger.global_position.x - ORIGIN.x
	world.queue_free()
	await tree.process_frame

	if phase == CHARGE:
		push_error("open ram never resolved — charged %.1f m and still CHARGE" % dx)
		return 1
	if phase != RECOVER and phase != SEARCH:
		push_error("open ram (no wall) resolved to phase %d, expected RECOVER" % phase)
		return 1
	if dx > 20.0:
		push_error("open ram ran %.1f m before the failsafe (cap is charge_max_dist_m)" % dx)
		return 1
	return 0
