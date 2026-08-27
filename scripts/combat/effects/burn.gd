class_name Burn
extends Effect

## Tick DPS for duration_sec. Both must be > 0.

@export var dps: float = 6.0
@export var duration_sec: float = 0.5


static func with(burn_dps: float, burn_duration: float) -> Burn:
	var effect := Burn.new()
	effect.dps = burn_dps
	effect.duration_sec = burn_duration
	return effect


func apply(body: CharacterBody3D, from: Variant) -> void:
	if dps <= 0.0 or duration_sec <= 0.0:
		push_error("Burn.dps and duration_sec must be > 0; omit Burn to skip")
		assert(dps > 0.0 and duration_sec > 0.0)
		return
	if body is Character:
		(body as Character).apply_burn(dps, duration_sec, from)
