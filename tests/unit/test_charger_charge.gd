class_name TestChargerCharge
extends RefCounted

## Pure logic for the Charger redesign: commit-window steering, whiff / band
## thresholds, and the once-per-engagement feint roll.

const ChargerChargeScript := preload("res://scripts/monsters/charger_charge.gd")


func run() -> int:
	var failures := 0
	failures += _test_commit_window_steers_then_freezes()
	failures += _test_band_and_whiff_thresholds()
	failures += _test_feint_rolls_once_per_engagement()
	return failures


func _test_commit_window_steers_then_freezes() -> int:
	var charge := ChargerChargeScript.new()
	charge.begin_charge(Vector3.FORWARD)  # locked_dir = (0, 0, -1)
	var toward := Vector3(1.0, 0.0, -1.0)  # 45° to the charger's right

	# Inside the commit window: repeated steering should bend locked_dir toward it.
	var before := charge.locked_dir
	for _i in 10:
		charge.steer_locked_dir(toward, ChargerChargeScript.COMMIT_TURN_RAD, 1.0 / 60.0)
	var bent := charge.locked_dir
	if before.angle_to(bent) < 0.05:
		push_error("commit-window steering did not turn locked_dir toward the target")
		return 1
	if bent.angle_to(toward.normalized()) > 0.35:
		push_error("commit-window steering overshot / did not track the target")
		return 1

	# is_committed() gates whether the Charger keeps calling steer_locked_dir.
	if ChargerChargeScript.is_committed(2.9, 3.0):
		push_error("is_committed true before the commit distance")
		return 1
	if not ChargerChargeScript.is_committed(3.1, 3.0):
		push_error("is_committed false past the commit distance")
		return 1
	return 0


func _test_band_and_whiff_thresholds() -> int:
	if ChargerChargeScript.in_charge_band(3.0, 4.0, 14.0):
		push_error("in_charge_band true below the band")
		return 1
	if not ChargerChargeScript.in_charge_band(9.0, 4.0, 14.0):
		push_error("in_charge_band false inside the band")
		return 1
	if ChargerChargeScript.in_charge_band(20.0, 4.0, 14.0):
		push_error("in_charge_band true above the band")
		return 1
	if ChargerChargeScript.whiffed(14.9, 15.0):
		push_error("whiffed true before the cap")
		return 1
	if not ChargerChargeScript.whiffed(15.1, 15.0):
		push_error("whiffed false past the cap")
		return 1
	return 0


func _test_feint_rolls_once_per_engagement() -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var charge := ChargerChargeScript.new()

	# chance 1.0 always plans a feint; begin_feint() consumes it for the engagement.
	if not charge.roll_feint(rng, 1.0):
		push_error("roll_feint(chance=1.0) did not plan a feint")
		return 1
	charge.begin_feint()
	if charge.roll_feint(rng, 1.0):
		push_error("roll_feint fired a second feint in one engagement")
		return 1

	# reset() clears feint_used so the next engagement can feint again.
	charge.reset()
	if not charge.roll_feint(rng, 1.0):
		push_error("roll_feint stayed blocked after reset()")
		return 1

	# chance 0.0 never plans a feint.
	charge.reset()
	if charge.roll_feint(rng, 0.0):
		push_error("roll_feint(chance=0.0) planned a feint")
		return 1
	return 0
