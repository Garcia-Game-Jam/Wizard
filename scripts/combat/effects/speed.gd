class_name Speed
extends Effect

## Move multiplier for duration_sec. mult must not be 1. <1 slow, >1 haste.

@export var mult: float = 0.6
@export var duration_sec: float = 0.5


static func with(speed_mult: float, speed_duration: float) -> Speed:
	var effect := Speed.new()
	effect.mult = speed_mult
	effect.duration_sec = speed_duration
	return effect


func apply(body: CharacterBody3D, _from: Variant) -> void:
	if is_equal_approx(mult, 1.0) or duration_sec <= 0.0:
		push_error("Speed.mult must not be 1 and duration_sec must be > 0; omit Speed to skip")
		assert(not is_equal_approx(mult, 1.0) and duration_sec > 0.0)
		return
	if body is Character:
		(body as Character).apply_speed_boost(duration_sec, mult)
