class_name Health
extends Node

## Authored HP pool. Parent characters call take_damage; this node owns current/max.

signal damaged(amount: float, from: Variant)
signal died(from: Variant)
signal changed(current: float, maximum: float)

const DEFAULT_MAX_HEALTH := 100.0

@export_range(1.0, 1000.0, 1.0) var max_health: float = DEFAULT_MAX_HEALTH:
	set(value):
		max_health = maxf(value, 1.0)
		if current_health > max_health:
			current_health = max_health
		_emit_changed()

var current_health: float = DEFAULT_MAX_HEALTH


func _ready() -> void:
	current_health = max_health


func is_dead() -> bool:
	return current_health <= 0.0


func ratio() -> float:
	if max_health <= 0.001:
		return 0.0
	return clampf(current_health / max_health, 0.0, 1.0)


func take_damage(amount: float, from: Variant = null) -> void:
	if is_dead():
		return
	var hit := maxf(amount, 0.0)
	if hit <= 0.0:
		return
	current_health = maxf(0.0, current_health - hit)
	damaged.emit(hit, from)
	_emit_changed()
	if is_dead():
		died.emit(from)


## Ratio just before a hit of `amount` landed, for threshold-crossing reactions.
func ratio_before(amount: float) -> float:
	if max_health <= 0.001:
		return 0.0
	return clampf((current_health + maxf(amount, 0.0)) / max_health, 0.0, 1.0)


## Spend the whole pool so death always travels the same signal path.
func kill(from: Variant = null) -> void:
	take_damage(current_health, from)


func heal(amount: float) -> void:
	if is_dead():
		return
	current_health = clampf(current_health + maxf(amount, 0.0), 0.0, max_health)
	_emit_changed()


## Restore a dead (or living) pool to full. Does not emit `died`.
func revive() -> void:
	current_health = max_health
	_emit_changed()


func _emit_changed() -> void:
	if not is_inside_tree():
		return
	changed.emit(current_health, max_health)
