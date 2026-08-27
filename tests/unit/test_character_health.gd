extends RefCounted

## The shared HP lifecycle. Players and monsters run the same assertions here:
## each owns one Health child, spends only its own pool, and dies once.

const PlayerScene := preload("res://scenes/characters/playable_character.tscn")
const WretchScene := preload("res://scenes/monsters/evaluating/wretch.tscn")


func run() -> int:
	var failures := 0
	failures += _test_shared_lifecycle(PlayerScene, "Player")
	failures += _test_shared_lifecycle(WretchScene, "Wretch")
	failures += _test_kill_matches_lethal_damage()
	failures += _test_pools_are_independent()
	failures += _test_revive_restores_combat()
	failures += _test_replicated_health_emits_death()
	return failures


## Damage, healing, death, and teardown, asserted identically for every type.
func _test_shared_lifecycle(scene: PackedScene, label: String) -> int:
	var holder := _holder()
	if holder == null:
		return 1
	var character := scene.instantiate() as Character
	holder.add_child(character)
	var err := ""
	var pool := character.health
	if pool == null or pool.max_health <= 0.0:
		err = "%s should author its own Health child with max HP" % label
	else:
		var max_hp := pool.max_health
		var deaths := [0]
		pool.died.connect(func(_from: Variant) -> void: deaths[0] += 1)
		pool.take_damage(max_hp * 0.25)
		if not character.is_alive() or not is_equal_approx(character.health_ratio(), 0.75):
			err = "%s should sit at 75%% HP after a quarter hit" % label
		else:
			pool.heal(max_hp * 10.0)
			if not is_equal_approx(pool.current_health, max_hp):
				err = "%s healing should clamp at its own max HP" % label
			else:
				err = _assert_death_teardown(character, label, deaths)
	holder.queue_free()
	if err.is_empty():
		return 0
	push_error(err)
	return 1


func _assert_death_teardown(character: Character, label: String, deaths: Array) -> String:
	var pool := character.health
	pool.take_damage(pool.max_health * 2.0)
	if character.is_alive() or not is_equal_approx(pool.current_health, 0.0):
		return "%s should be dead once the pool empties" % label
	if deaths[0] != 1:
		return "%s should report death once, got %d" % [label, deaths[0]]
	if character.is_physics_processing():
		return "%s should stop ticking physics on death" % label
	for group in character._combat_groups():
		if character.is_in_group(group):
			return "%s should leave the %s group on death" % [label, group]
	## Overkill after death must not raise a second died.
	pool.take_damage(pool.max_health)
	if deaths[0] != 1:
		return "%s should not die twice, got %d" % [label, deaths[0]]
	return ""


func _test_kill_matches_lethal_damage() -> int:
	var holder := _holder()
	if holder == null:
		return 1
	var killed := WretchScene.instantiate() as Character
	var damaged := WretchScene.instantiate() as Character
	holder.add_child(killed)
	holder.add_child(damaged)
	killed.health.kill()
	damaged.health.take_damage(damaged.health.max_health)
	var same := (
		killed.is_alive() == damaged.is_alive()
		and is_equal_approx(killed.health.current_health, damaged.health.current_health)
	)
	holder.queue_free()
	if killed.is_alive() or not same:
		push_error("kill() and lethal damage should reach the same end state")
		return 1
	return 0


func _test_pools_are_independent() -> int:
	var holder := _holder()
	if holder == null:
		return 1
	var hurt := WretchScene.instantiate() as Character
	var bystander := WretchScene.instantiate() as Character
	holder.add_child(hurt)
	holder.add_child(bystander)
	hurt.health.take_damage(hurt.health.max_health * 0.5)
	var isolated := (
		is_equal_approx(hurt.health_ratio(), 0.5)
		and is_equal_approx(bystander.health_ratio(), 1.0)
	)
	holder.queue_free()
	if not isolated:
		push_error("Each monster should spend only its own HP pool")
		return 1
	return 0


func _test_revive_restores_combat() -> int:
	var holder := _holder()
	if holder == null:
		return 1
	var character := PlayerScene.instantiate() as PlayableCharacter
	holder.add_child(character)
	character.health.kill()
	character.health.revive()
	character.restore_after_revive()
	character.global_position = Vector3(2.0, 1.0, 3.0)
	var ok := (
		character.is_alive()
		and is_equal_approx(character.health.current_health, character.health.max_health)
		and character.is_physics_processing()
		and character.global_position.is_equal_approx(Vector3(2.0, 1.0, 3.0))
	)
	holder.queue_free()
	if not ok:
		push_error("revive should restore HP, physics, and allow a pit teleport")
		return 1
	return 0


func _test_replicated_health_emits_death() -> int:
	var holder := _holder()
	if holder == null:
		return 1
	var character := PlayerScene.instantiate() as Character
	holder.add_child(character)
	var deaths := [0]
	character.health.died.connect(func(_from: Variant) -> void: deaths[0] += 1)
	character.health.current_health = 0.0
	holder.queue_free()
	if deaths[0] != 1:
		push_error("Writing HP to 0 (netfox restore) should emit died once, got %d" % deaths[0])
		return 1
	return 0


func _holder() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		push_error("Expected a SceneTree for character health tests")
		return null
	var holder := Node.new()
	tree.root.add_child(holder)
	return holder
