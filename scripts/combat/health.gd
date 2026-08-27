class_name Health
extends Node

## Authored HP pool. Parent characters call take_damage; this node owns current/max.
## `current_health` is rewindable character state — netfox writes it on remotes.
## Death teardown must reverse when this value returns above 0. Do not
## queue_free a body whose HP can come back this tick; arena dump clear is
## the real despawn.

signal damaged(amount: float, from: Variant)
signal died(from: Variant)
signal changed(current: float, maximum: float)
## HP crossed back above 0 (host revive or rewind restore). Teardown must reverse.
signal revived

const DEFAULT_MAX_HEALTH := 100.0

@export_range(1.0, 1000.0, 1.0) var max_health: float = DEFAULT_MAX_HEALTH:
	set(value):
		max_health = maxf(value, 1.0)
		if current_health > max_health:
			current_health = max_health
		_emit_changed()

var current_health: float = DEFAULT_MAX_HEALTH:
	set(value):
		var next := clampf(value, 0.0, max_health)
		if is_equal_approx(current_health, next):
			return
		var was_dead := current_health <= 0.0
		current_health = next
		_emit_changed()
		## Host take_damage emits `died` with a source. Remotes get HP from
		## RollbackSynchronizer writes and still need the death signal.
		if _host_apply_depth == 0 and not was_dead and current_health <= 0.0:
			died.emit(null)
		if was_dead and current_health > 0.0:
			revived.emit()

var _host_apply_depth: int = 0


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
	_host_apply_depth += 1
	current_health = maxf(0.0, current_health - hit)
	_host_apply_depth -= 1
	damaged.emit(hit, from)
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


## Restore a dead (or living) pool to full. Does not emit `died`. Emits `revived`
## when the pool was empty.
func revive() -> void:
	current_health = max_health


func _emit_changed() -> void:
	if not is_inside_tree():
		return
	changed.emit(current_health, max_health)
