class_name WardRuntime
extends Resource

## Per-actor live ward HP and recast lock. Seeded from the shared spell template.

var max_hp := 40.0
var hp := 40.0
var regen_delay_sec := 1.0
var regen_per_sec := 10.0
var time_since_cast := 0.0
var cooldown_until_msec := 0
var shatter_regen_scale := 1.0


func seed_from_spell(spell: Resource) -> void:
	if spell == null:
		reset_hp()
		return
	var authored := float(spell.get("max_health"))
	max_hp = maxf(authored, 1.0) if authored > 0.0 else 40.0
	regen_delay_sec = maxf(float(spell.get("regen_delay_sec")), 0.0)
	regen_per_sec = maxf(float(spell.get("regen_per_sec")), 0.0)
	cooldown_until_msec = 0
	shatter_regen_scale = 1.0
	reset_hp()


func seed_from_max(max_hp_value: float, delay_sec: float, regen_hp: float) -> void:
	max_hp = maxf(max_hp_value, 1.0)
	regen_delay_sec = maxf(delay_sec, 0.0)
	regen_per_sec = maxf(regen_hp, 0.0)
	cooldown_until_msec = 0
	shatter_regen_scale = 1.0
	reset_hp()


func reset_hp() -> void:
	hp = max_hp
	time_since_cast = 0.0


func apply_shatter_regen_delay(authored_delay_sec: float) -> float:
	var delay := maxf(authored_delay_sec, 0.0)
	if shatter_regen_scale > 1.001:
		delay *= shatter_regen_scale
		shatter_regen_scale = 1.0
	regen_delay_sec = delay
	return delay


func remaining_cooldown_sec() -> float:
	if cooldown_until_msec <= 0:
		return 0.0
	var left: int = cooldown_until_msec - Time.get_ticks_msec()
	if left <= 0:
		cooldown_until_msec = 0
		return 0.0
	return float(left) / 1000.0
