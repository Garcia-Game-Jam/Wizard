#!/usr/bin/env -S godot --headless --script
extends SceneTree

## Regenerates assets/props/stone_mesh.res and stone_collision.res from StoneMeshBuilder.

const StoneMeshBuilderScript := preload("res://scripts/environment/stone_mesh_builder.gd")


func _init() -> void:
	var err: Error = StoneMeshBuilderScript.save_mesh()
	if err != OK:
		push_error("Failed to save stone mesh: %s" % error_string(err))
		quit(1)
		return
	print("Wrote ", StoneMeshBuilderScript.MESH_PATH)

	err = StoneMeshBuilderScript.save_collision_shape()
	if err != OK:
		push_error("Failed to save stone collision shape: %s" % error_string(err))
		quit(1)
		return
	print("Wrote ", StoneMeshBuilderScript.SHAPE_PATH)
	quit(0)
