class_name TestKnockGroundMove
extends RefCounted

## Walk overwrites xz every tick. Knock must keep horizontal like dash.

const PlayerScene := preload("res://scenes/characters/player.tscn")
const ChargerScene := preload("res://scenes/monsters/charger.tscn")
const SlideSurfaceScript := preload("res://scripts/slide_surface.gd")
const MonsterAIScript := preload("res://scripts/monsters/monster_ai.gd")
const TICK := 1.0 / 60.0


func run(tree: SceneTree) -> int:
	var failures := 0
	failures += _test_walk_does_not_replace_knock_xz(tree)
	failures += _test_monster_gravity_does_not_eat_knock_up(tree)
	failures += _test_monster_air_idle_does_not_replace_xz(tree)
	return failures


func _test_walk_does_not_replace_knock_xz(tree: SceneTree) -> int:
	var world := Node3D.new()
	tree.root.add_child(world)
	_add_floor(world)
	var player := PlayerScene.instantiate() as Player
	world.add_child(player)
	player.global_position = Vector3(0.0, 0.94, 0.0)
	player.velocity = Vector3.ZERO
	player.apply_knockback(Vector3.RIGHT, Vector3(9.0, 3.5, 0.0))
	var knock_x := player.velocity.x
	var input := PlayerNetInput.new()
	input.movement = Vector2(0.0, 1.0)
	SlideSurfaceScript.apply_ground_move(
		player,
		player.head,
		18.0,
		TICK,
		1.0,
		player.is_knocked(),
		false,
		input
	)
	var kept := absf(player.velocity.x - knock_x) < 0.05
	world.queue_free()
	if kept:
		return 0
	push_error(
		"Ground walk must not replace knock xz (knock_x=%.2f now=%.2f)"
		% [knock_x, player.velocity.x]
	)
	return 1


func _add_floor(parent: Node) -> void:
	var static_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 1.0, 20.0)
	shape.shape = box
	static_body.add_child(shape)
	parent.add_child(static_body)
	static_body.global_position = Vector3(0.0, -0.5, 0.0)
	static_body.collision_layer = 1
	static_body.collision_mask = 0


func _test_monster_gravity_does_not_eat_knock_up(tree: SceneTree) -> int:
	var world := Node3D.new()
	tree.root.add_child(world)
	_add_floor(world)
	var player := PlayerScene.instantiate() as Player
	world.add_child(player)
	player.global_position = Vector3(0.0, 0.94, 0.0)
	player.velocity = Vector3.ZERO
	for _i in 8:
		player.move_and_slide()
	player.apply_knockback(Vector3.RIGHT, Vector3(9.0, 3.5, 0.0))
	MonsterAIScript.apply_gravity(player, TICK, 18.0)
	var kept_up := player.velocity.y > 3.0
	world.queue_free()
	if kept_up:
		return 0
	push_error(
		"Monster gravity must not zero knock-up on the floor (vy=%.2f)" % player.velocity.y
	)
	return 1


func _test_monster_air_idle_does_not_replace_xz(tree: SceneTree) -> int:
	var world := Node3D.new()
	tree.root.add_child(world)
	var monster := ChargerScene.instantiate() as Monster
	world.add_child(monster)
	monster.global_position = Vector3(0.0, 6.0, 0.0)
	monster.velocity = Vector3(9.0, 3.5, 0.0)
	monster.call("_simulate_monster", TICK)
	var kept := absf(monster.velocity.x - 9.0) < 0.05
	world.queue_free()
	if kept:
		return 0
	push_error(
		"Airborne monster must not walk-replace xz (now=%.2f)" % monster.velocity.x
	)
	return 1
