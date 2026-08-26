extends Node

## Authority clients record movement samples; host stores and broadcasts them.

const MIN_SPEED := 0.15
const MIN_DISTANCE := 0.38

var _player: CharacterBody3D
var _last_record_position: Vector3
var _was_on_floor: bool = false
var _next_seq: int = 0


func setup(player: CharacterBody3D) -> void:
	_player = player
	_last_record_position = player.global_position
	_next_seq = 0


func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	if GameState.is_multiplayer and not _player.is_multiplayer_authority():
		return

	if not _player.is_on_floor():
		_was_on_floor = false
		return

	var current_position := _player.global_position
	if not _was_on_floor:
		_last_record_position = current_position
		_was_on_floor = true
		return

	var horizontal_speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	if horizontal_speed < MIN_SPEED:
		_last_record_position = current_position
		return

	var flat_current := Vector3(current_position.x, 0.0, current_position.z)
	var flat_last := Vector3(_last_record_position.x, 0.0, _last_record_position.z)
	if flat_current.distance_to(flat_last) < MIN_DISTANCE:
		return

	TrailRegistry.submit_sample(_next_seq, current_position.x, current_position.z)
	_next_seq += 1
	_last_record_position = current_position
