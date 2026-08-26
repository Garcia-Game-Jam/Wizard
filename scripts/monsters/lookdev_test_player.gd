@tool
extends CharacterBody3D

## Lookdev dummy in the `player` group so monster senses can lock on.
## Armed by MonsterWorkspace; stays out of the group while hidden.
## Not a Character, so senses treat it as always alive.


func _enter_tree() -> void:
	collision_layer = 1
	collision_mask = 1
	floor_snap_length = 0.15
	if visible:
		arm()


func arm() -> void:
	visible = true
	if not is_in_group("player"):
		add_to_group("player")


func disarm() -> void:
	visible = false
	if is_in_group("player"):
		remove_from_group("player")
