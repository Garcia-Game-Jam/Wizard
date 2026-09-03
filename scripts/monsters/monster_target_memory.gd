class_name MonsterTargetMemory
extends RefCounted

## Last-known world position of the prioritized player. Lets a monster keep
## approaching after it loses live senses, then forget after `memory_sec`.
## Owned by Monster as `_target_memory` (mirrors MonsterChaseMove).

var memory_sec: float = 6.0

var _has_goal: bool = false
var _goal: Vector3 = Vector3.ZERO
var _target_id: int = 0
var _age: float = 0.0


func configure(p_memory_sec: float) -> void:
	memory_sec = maxf(p_memory_sec, 0.0)


## Refresh from a live sighting.
func note_seen(seen_id: int, world_pos: Vector3) -> void:
	_has_goal = true
	_goal = world_pos
	_target_id = seen_id
	_age = 0.0


func tick(delta: float) -> void:
	if not _has_goal:
		return
	_age += maxf(delta, 0.0)
	if _age >= memory_sec:
		clear()


func clear() -> void:
	_has_goal = false
	_goal = Vector3.ZERO
	_target_id = 0
	_age = 0.0


func has_goal() -> bool:
	return _has_goal


func last_goal() -> Vector3:
	return _goal


func target_id() -> int:
	return _target_id
