class_name TestSpellWorldSync
extends RefCounted

const SyncScript := preload("res://scripts/spells/spell_world_sync.gd")


func run() -> int:
	var failures := 0
	failures += _test_cell_id_round_trip()
	failures += _test_make_spawn_id_format()
	failures += _test_register_and_find()
	return failures


func _test_cell_id_round_trip() -> int:
	var cell := Vector2i(4, 9)
	var id := SyncScript.make_cell_id(cell)
	var parsed := SyncScript.parse_cell_id(id)
	if parsed != cell:
		push_error("Expected cell id round-trip to preserve Vector2i")
		return 1
	return 0


func _test_make_spawn_id_format() -> int:
	var id := SyncScript.make_spawn_id(null)
	if id.is_empty() or not id.contains("_"):
		push_error("Expected spawn id to look like peer_usec")
		return 1
	return 0


func _test_register_and_find() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("Expected SceneTree for register/find test")
		return 1
	var root := Node3D.new()
	tree.root.add_child(root)
	var orb := Node3D.new()
	orb.name = "TestOrb"
	root.add_child(orb)
	SyncScript.register(orb, SyncScript.KIND_LIGHT_BALL, "peer_123")
	var found := SyncScript.find(tree, SyncScript.KIND_LIGHT_BALL, "peer_123")
	var ok := found == orb and SyncScript.get_id(orb) == "peer_123"
	orb.queue_free()
	root.queue_free()
	if not ok:
		push_error("Expected register/find to resolve spell world object by id")
		return 1
	return 0
