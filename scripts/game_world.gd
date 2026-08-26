class_name GameWorld
extends RefCounted

## Resolves the active match/world root when GameApp owns the scene tree.


static func find_match_root(tree: SceneTree) -> Node:
	if tree == null:
		return null
	var app := tree.get_first_node_in_group("game_app")
	if app != null and app.has_method("get_match_root"):
		var match_root: Node = app.call("get_match_root")
		if match_root != null:
			return match_root
	return tree.current_scene
