class_name ColosseumGate
extends Node3D

## Domed colosseum gate: the inlaid door slides down into the floor as this
## gate's spawn pad telegraph lights up. Driven by SpawnTelegraph — set_open_amount
## shares the same 0..1 fade SpawnTelegraph already uses for the spot/beam/ring
## glow, so the door finishes sinking right as the monster dump lands on the pad.
## Author under scenes/arenas/*: authored child names are fixed — Door, and
## Door/CollisionShape3D — do not rename without updating this script.

## Door's authored (closed) local Y — the door sits flush in the frame here.
const CLOSED_LOCAL_Y := 3.4
## How far the door sinks at full open. Must clear the door's own half-height
## (3.4) so the top edge drops below the floor instead of poking through it.
const OPEN_DROP := 7.2

var _open_amount := 0.0

@onready var _door: Node3D = get_node_or_null("Door")
@onready var _door_collision: CollisionShape3D = get_node_or_null("Door/CollisionShape3D")


## amount 0 = closed (door inlaid in the frame), 1 = fully sunk into the floor.
func set_open_amount(amount: float) -> void:
	var t := clampf(amount, 0.0, 1.0)
	if is_equal_approx(t, _open_amount):
		return
	_open_amount = t
	if _door == null:
		return
	var pos := _door.position
	pos.y = CLOSED_LOCAL_Y - OPEN_DROP * t
	_door.position = pos
	if _door_collision != null:
		## Fully open: stop colliding rather than leave a buried shape live.
		_door_collision.disabled = t > 0.98
