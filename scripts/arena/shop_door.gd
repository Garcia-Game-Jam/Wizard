@tool
class_name ShopDoor
extends Node3D

## Double door for a ShopStructure entrance bay — swings both leaves open on
## outer-edge hinges (the pier side of each leaf; see _add_bay's door branch
## in shop_structure.gd, which builds DoorHingeLeft/DoorHingeRight and calls
## configure() with them before this node enters the tree). Opening is
## triggered externally via open() (see ShopSpawnController's automatic
## grand-opening) rather than a player interaction here.
##
## Each leaf carries a CollisionShape3D (see _add_glass_pane's framed arg)
## that's disabled once the door has swung open past a hair, matching
## ColosseumGate's "don't leave a live shape behind an open door" habit.

const OPEN_ANGLE_DEG := 105.0
const OPEN_SPEED := 2.4

var _hinge_left: Node3D
var _hinge_right: Node3D
var _leaf_collisions: Array[CollisionShape3D] = []
var _open_amount := 0.0
var _target_open := 0.0


## Must be called before this node enters the tree (i.e. before add_child) —
## mirrors ShopDisplayPedestal.configure()'s same contract.
func configure(hinge_left: Node3D, hinge_right: Node3D) -> void:
	_hinge_left = hinge_left
	_hinge_right = hinge_right
	for hinge in [hinge_left, hinge_right]:
		for leaf in hinge.get_children():
			var collision := leaf.get_node_or_null("CollisionShape3D") as CollisionShape3D
			if collision != null:
				_leaf_collisions.append(collision)


func _process(delta: float) -> void:
	if is_equal_approx(_open_amount, _target_open):
		return
	_open_amount = move_toward(_open_amount, _target_open, OPEN_SPEED * delta)
	var angle := deg_to_rad(OPEN_ANGLE_DEG) * _open_amount
	if _hinge_left != null:
		_hinge_left.rotation.y = -angle
	if _hinge_right != null:
		_hinge_right.rotation.y = angle
	for collision in _leaf_collisions:
		collision.disabled = _open_amount > 0.05


## Opens the door on command — used for the shop's own automatic
## grand-opening once ShopSpawnController finishes rising it into place.
func open() -> void:
	_target_open = 1.0
