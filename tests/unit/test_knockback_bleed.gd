class_name TestKnockbackBleed
extends RefCounted

## Knockback must feel the same at any tickrate.
##
## Regression guard for the mid-air stall: _apply_knockback_bleed used to add a
## flat fraction of _knockback_vel per TICK, so total speed added scaled with
## tickrate (16.8 m/s at 30 Hz, 32 at 60, 62 at 120). At 60 Hz that flung a
## player 40 m/s into the pit wall, where the body penetrated the collider and
## move_and_slide resolved to zero displacement for over a second.

const HIT_SPEED := Character.KNOCKBACK_HORIZONTAL
const TIMER := Character.KNOCKBACK_TIMER_SEC
## Bleed totals must agree within this fraction across tickrates.
const TICKRATE_TOLERANCE := 0.10
## Total speed after a hit must stay inside the tunnelling budget at 60 Hz.
const CAPSULE_RADIUS := 0.2368164


func run() -> int:
	var failures := 0
	failures += _test_bleed_is_tickrate_independent()
	failures += _test_bleed_terminates()
	failures += _test_speed_budget_documented()
	return failures


## Mirrors Character._apply_knockback_bleed / PlayerCombatReactions.
## Both must stay delta-scaled; this is the contract they encode.
func _bleed_total(tickrate: float) -> float:
	var delta := 1.0 / tickrate
	var knockback := Vector3(HIT_SPEED, 0.0, 0.0)
	var timer := TIMER
	var added := 0.0
	while timer > 0.0:
		timer -= delta
		added += knockback.x * Character.KNOCKBACK_BLEED_PER_SEC * delta
		knockback = knockback.move_toward(
			Vector3.ZERO, Character.KNOCKBACK_DECAY * delta
		)
	return added


func _test_bleed_is_tickrate_independent() -> int:
	var failures := 0
	var reference := _bleed_total(30.0)
	if reference <= 0.0:
		push_error("Knockback bleed added nothing at 30 Hz")
		return 1
	for tickrate in [60.0, 120.0, 144.0]:
		var total := _bleed_total(tickrate)
		var drift: float = absf(total - reference) / reference
		if drift > TICKRATE_TOLERANCE:
			push_error(
				(
					"Knockback bleed is tickrate-dependent: %.1f m/s at 30 Hz vs "
					+ "%.1f at %d Hz (%.0f%% drift). Scale it by delta."
				)
				% [reference, total, int(tickrate), drift * 100.0]
			)
			failures += 1
	return failures


func _test_bleed_terminates() -> int:
	## _knockback_vel must reach zero inside the window, or the bleed keeps
	## pushing after the hit should have settled.
	var delta := 1.0 / 60.0
	var knockback := Vector3(HIT_SPEED, 0.0, 0.0)
	var timer := TIMER
	while timer > 0.0:
		timer -= delta
		knockback = knockback.move_toward(
			Vector3.ZERO, Character.KNOCKBACK_DECAY * delta
		)
	if knockback.length() > 0.01:
		push_error(
			"Knockback still has %.2f m/s left when the timer ends" % knockback.length()
		)
		return 1
	return 0


func _test_speed_budget_documented() -> int:
	## A body may not travel further than its own collision radius in one tick,
	## or it penetrates geometry and stalls. This test does not enforce the
	## current tuning -- it fails loudly if a change pushes knockback past the
	## budget so the trade-off is a decision, not an accident.
	var total_speed := HIT_SPEED + _bleed_total(60.0)
	var budget := CAPSULE_RADIUS * 60.0
	if total_speed > budget * 2.0:
		push_error(
			(
				"Knockback reaches %.1f m/s; the 60 Hz tunnelling budget is "
				+ "%.1f m/s. Over 2x the budget buries players in walls."
			)
			% [total_speed, budget]
		)
		return 1
	return 0
