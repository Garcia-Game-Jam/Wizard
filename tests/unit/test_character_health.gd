extends RefCounted

## The shared HP lifecycle. Players and monsters run the same assertions here:
## each owns max HP on the character root, spends only its own pool, and dies once.

const PlayerScene := preload("res://scenes/characters/player.tscn")
const WretchScene := preload("res://scenes/monsters/evaluating/wretch.tscn")


func run() -> int:
	var failures := 0
	failures += _test_shared_lifecycle(PlayerScene, "Player")
	failures += _test_shared_lifecycle(WretchScene, "Wretch")
	failures += _test_kill_matches_lethal_damage()
	failures += _test_pools_are_independent()
	failures += _test_revive_restores_combat()
	failures += _test_replicated_health_emits_death()
	failures += _test_replicated_health_restores_combat()
	failures += _test_monster_death_stays_in_tree()
	return failures


## Damage, healing, death, and teardown, asserted identically for every type.
func _test_shared_lifecycle(scene: PackedScene, label: String) -> int:
	var holder := _holder()
	if holder == null:
		return 1
	var character := scene.instantiate() as Character
	holder.add_child(character)
	var err := ""
	if character.max_health <= 0.0:
		err = "%s should author max HP on the character root" % label
	else:
		var max_hp := character.max_health
		var deaths := [0]
		character.died.connect(func(_from: Variant) -> void: deaths[0] += 1)
		character.take_damage(max_hp * 0.25)
		if not character.is_alive() or not is_equal_approx(character.health_ratio(), 0.75):
			err = "%s should sit at 75%% HP after a quarter hit" % label
		else:
			character.heal(max_hp * 10.0)
			if not is_equal_approx(character.current_health, max_hp):
				err = "%s healing should clamp at its own max HP" % label
			else:
				err = _assert_death_teardown(character, label, deaths)
	holder.queue_free()
	if err.is_empty():
		return 0
	push_error(err)
	return 1


func _assert_death_teardown(character: Character, label: String, deaths: Array) -> String:
	character.take_damage(character.max_health * 2.0)
	if character.is_alive() or not is_equal_approx(character.current_health, 0.0):
		return "%s should be dead once the pool empties" % label
	if deaths[0] != 1:
		return "%s should report death once, got %d" % [label, deaths[0]]
	if not character.is_death_physics() or not character.is_physics_processing():
		return "%s should limp on engine physics after death" % label
	for group in character._combat_groups():
		if character.is_in_group(group):
			return "%s should leave the %s group on death" % [label, group]
	## Overkill after death must not raise a second died.
	character.take_damage(character.max_health)
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
	killed.kill()
	damaged.take_damage(damaged.max_health)
	var same := (
		killed.is_alive() == damaged.is_alive()
		and is_equal_approx(killed.current_health, damaged.current_health)
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
	hurt.take_damage(hurt.max_health * 0.5)
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
	var character := PlayerScene.instantiate() as Player
	holder.add_child(character)
	character.kill()
	character.revive()
	character.restore_after_revive()
	character.global_position = Vector3(2.0, 1.0, 3.0)
	var ok := (
		character.is_alive()
		and is_equal_approx(character.current_health, character.max_health)
		and character.is_physics_processing()
		and not character.is_death_physics()
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
	character.died.connect(func(_from: Variant) -> void: deaths[0] += 1)
	character.current_health = 0.0
	holder.queue_free()
	if deaths[0] != 1:
		push_error("Writing HP to 0 (netfox restore) should emit died once, got %d" % deaths[0])
		return 1
	return 0


func _test_replicated_health_restores_combat() -> int:
	var holder := _holder()
	if holder == null:
		return 1
	var character := PlayerScene.instantiate() as Character
	holder.add_child(character)
	character.current_health = 0.0
	character.current_health = character.max_health
	var ok := (
		character.is_alive()
		and character.is_physics_processing()
		and not character.is_death_physics()
		and character.is_in_group(&"combat_target")
	)
	## Presentation stays until revive(); sim reverse is what rewind must do.
	var leftover := false
	for child in holder.get_children():
		if child is MonsterCorpse and not child.is_queued_for_deletion():
			leftover = true
			break
	holder.queue_free()
	if not ok:
		push_error("Writing HP back above 0 (rewind) should reverse death sim teardown")
		return 1
	if not leftover:
		push_error("HP rewind must leave committed death presentation until revive()")
		return 1
	return 0


func _test_monster_death_stays_in_tree() -> int:
	var holder := _holder()
	if holder == null:
		return 1
	var monster := WretchScene.instantiate() as Character
	holder.add_child(monster)
	monster.kill()
	var ok := (
		is_instance_valid(monster)
		and monster.is_inside_tree()
		and not monster.is_queued_for_deletion()
		and monster.is_death_physics()
		and not monster.is_alive()
	)
	holder.queue_free()
	if not ok:
		push_error("Dump monster death must limp in place, not free the node")
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
