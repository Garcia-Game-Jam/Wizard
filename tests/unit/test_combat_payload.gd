class_name TestCombatPayload
extends RefCounted

## Payload membership is the guard: Damage does not knock; projectile skips the
## caster; charger telegraph still ignores knock.

const PlayerScene := preload("res://scenes/characters/player.tscn")
const ChargerScene := preload("res://scenes/monsters/charger.tscn")
const FireballScene := preload("res://scenes/spells/fireball/fireball.tscn")
const StoneThrowScene := preload("res://scenes/spells/stone_throw/stone_throw.tscn")


func run(tree: SceneTree) -> int:
	var failures := 0
	failures += _test_damage_only_does_not_knock(tree)
	failures += _test_projectile_skips_caster(tree)
	failures += _test_overlapped_body_applies(tree)
	failures += _test_fireball_does_not_knock(tree)
	failures += _test_charger_telegraph_ignores_knock(tree)
	failures += _test_rewind_queue_applies_on_matching_tick(tree)
	return failures


func _holder(tree: SceneTree) -> Node3D:
	var holder := Node3D.new()
	tree.root.add_child(holder)
	return holder


func _test_damage_only_does_not_knock(tree: SceneTree) -> int:
	var holder := _holder(tree)
	var player := PlayerScene.instantiate() as Character
	holder.add_child(player)
	player.velocity = Vector3.ZERO
	var max_hp := player.max_health
	var payload := CombatPayload.new()
	payload.effects.append(Damage.with(10.0))
	player.apply(player, payload)
	var err := ""
	if is_equal_approx(player.current_health, max_hp):
		err = "Damage-only payload should spend HP"
	elif player.velocity.length_squared() > 0.01:
		err = "Damage-only payload must not knock (velocity %s)" % player.velocity
	holder.queue_free()
	if err.is_empty():
		return 0
	push_error(err)
	return 1


func _test_projectile_skips_caster(tree: SceneTree) -> int:
	var holder := _holder(tree)
	var caster := PlayerScene.instantiate() as Character
	var other := PlayerScene.instantiate() as Character
	holder.add_child(caster)
	holder.add_child(other)
	caster.global_position = Vector3.ZERO
	other.global_position = Vector3(0.12, 0.0, 0.0)
	var caster_hp := caster.current_health
	var other_hp := other.current_health
	var stone := StoneThrowScene.instantiate() as StoneThrowProjectile
	holder.add_child(stone)
	stone.setup_launch(Vector3(0.06, 0.36, 0.0), Vector3.FORWARD, caster)
	stone.call("_finish", true)
	var err := ""
	if not is_equal_approx(caster.current_health, caster_hp):
		err = "Projectile must skip the caster"
	elif is_equal_approx(other.current_health, other_hp):
		err = "Overlapping non-caster must take the payload"
	holder.queue_free()
	if err.is_empty():
		return 0
	push_error(err)
	return 1


func _test_overlapped_body_applies(tree: SceneTree) -> int:
	var holder := _holder(tree)
	var target := PlayerScene.instantiate() as Character
	holder.add_child(target)
	target.global_position = Vector3.ZERO
	var hp := target.current_health
	var stone := StoneThrowScene.instantiate() as StoneThrowProjectile
	holder.add_child(stone)
	stone.setup_launch(Vector3(0.0, 0.5, 0.0), Vector3.FORWARD)
	stone.call("_finish", true, [target])
	var ok := not is_equal_approx(target.current_health, hp)
	holder.queue_free()
	if not ok:
		push_error("An overlapped body passed to _finish must take damage")
		return 1
	return 0


func _test_fireball_does_not_knock(tree: SceneTree) -> int:
	var holder := _holder(tree)
	var player := PlayerScene.instantiate() as Character
	holder.add_child(player)
	player.global_position = Vector3.ZERO
	player.velocity = Vector3.ZERO
	var max_hp := player.max_health
	var ball := FireballScene.instantiate() as FireballProjectile
	holder.add_child(ball)
	ball.global_position = Vector3(0.0, 0.36, 0.0)
	ball.call("_finish", true)
	var err := ""
	if is_equal_approx(player.current_health, max_hp):
		err = "Fireball overlap should spend HP"
	elif player.velocity.length_squared() > 0.01:
		err = "Fireball payload is Damage-only; must not knock (velocity %s)" % player.velocity
	holder.queue_free()
	if err.is_empty():
		return 0
	push_error(err)
	return 1


func _test_charger_telegraph_ignores_knock(tree: SceneTree) -> int:
	var holder := _holder(tree)
	var charger := ChargerScene.instantiate() as Charger
	holder.add_child(charger)
	charger.global_position = Vector3.ZERO
	charger.velocity = Vector3.ZERO
	charger._phase = Charger.ChargePhase.TELEGRAPH
	var payload := CombatPayload.new()
	payload.effects.append(Knock.with(Vector3(9.0, 3.5, 0.0)))
	charger.apply(charger, payload)
	var err := ""
	if charger.velocity.length_squared() > 0.01:
		err = "Charger telegraph must ignore knock (velocity %s)" % charger.velocity
	holder.queue_free()
	if err.is_empty():
		return 0
	push_error(err)
	return 1


func _test_rewind_queue_applies_on_matching_tick(tree: SceneTree) -> int:
	var holder := _holder(tree)
	var target := PlayerScene.instantiate() as Character
	holder.add_child(target)
	var max_hp := target.max_health
	var payload := CombatPayload.new()
	payload.effects.append(Damage.with(10.0))
	target._queue_rewind_apply(null, payload, 5)
	target._flush_rewind_applies(4)
	var err := ""
	if not is_equal_approx(target.current_health, max_hp):
		err = "Queued payload must not spend until its tick"
	else:
		target._flush_rewind_applies(5)
		if is_equal_approx(target.current_health, max_hp):
			err = "Queued payload must spend on its tick"
		else:
			target.current_health = max_hp
			target._flush_rewind_applies(5)
			if is_equal_approx(target.current_health, max_hp):
				err = "Resim of the same tick must spend the queued payload again"
	holder.queue_free()
	if err.is_empty():
		return 0
	push_error(err)
	return 1
