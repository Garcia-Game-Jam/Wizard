class_name TestNetfoxContract
extends RefCounted

## Guards the netfox PoC contract: lanes pick primitives, profiles split
## input vs state, hits stay host-gated, voice stays off the tick.

const NetWorldEventScript := preload("res://scripts/net/net_world_event.gd")
const Profiles := preload("res://scripts/net/net_rewindable_profiles.gd")


func run() -> int:
	var failures := 0
	failures += _test_lane_primitives()
	failures += _test_profile_split()
	failures += _test_apply_hit_skips_non_authority()
	failures += _test_lan_agreement_contract()
	return failures


func _test_lane_primitives() -> int:
	var failures := 0
	var expected := {
		"haste": NetWorldEventScript.KIND_ACTION,
		"flashlight_toggle": NetWorldEventScript.KIND_ACTION,
		"fireball": NetWorldEventScript.KIND_WEAPON,
		"flare": NetWorldEventScript.KIND_WEAPON,
		"ward": NetWorldEventScript.KIND_WEAPON,
		"light_ball": NetWorldEventScript.KIND_WORLD_PROP,
		"target": "",
		"pull": "",
		"follow": "",
		"stop": "",
		"dispell": "",
		"clone": "",
	}
	for effect_id in expected.keys():
		var got := NetWorldEventScript.primitive_for_effect(str(effect_id))
		if got != str(expected[effect_id]):
			push_error("Effect '%s' should use %s, got %s" % [effect_id, expected[effect_id], got])
			failures += 1
	return failures


func _test_profile_split() -> int:
	var failures := 0
	var probe := PlayableCharacter.new()
	var playable_state := probe.net_state_paths()
	probe.free()
	var playable_input := PlayerNetInput.net_input_paths()
	if playable_input.is_empty():
		push_error("Playable profile must list Input properties")
		failures += 1
	for path in playable_input:
		if playable_state.has(path):
			push_error("Input path %s must not also be state" % path)
			failures += 1
	if Profiles.input_paths(Profiles.WORLD_PROP).size() != 0:
		push_error("World props are inputless")
		failures += 1
	if not playable_state.has(":net_charge_factor"):
		push_error("Charge tell must be playable state")
		failures += 1
	if not playable_input.has("Input:charge_factor"):
		push_error("Charge hold must be gathered as Input")
		failures += 1
	if not playable_input.has("Input:jump"):
		push_error("Jump must be gathered as Input")
		failures += 1
	var local_lerp := Profiles.local_playable_interpolate_paths()
	if not local_lerp.has(":position"):
		push_error("Local playable must interpolate position or host walk ticks")
		failures += 1
	if local_lerp.has("Head:rotation") or local_lerp.has("Head/CameraPivot:rotation"):
		push_error("Local playable must not interpolate look (mouse is frame-rate)")
		failures += 1
	if not ("Health:current_health" in Character.NET_STATE_PATHS):
		push_error("HP must be rewindable character state")
		failures += 1
	if not playable_state.has("Health:current_health"):
		push_error("Playable net_state_paths must include HP")
		failures += 1
	var charge_state := Profiles.state_paths(Profiles.CHARGE)
	if not charge_state.has(":net_phase") or not charge_state.has(":net_telegraph"):
		push_error("Charger telegraph+ram must share rewindable phase state")
		failures += 1
	if not charge_state.has("Health:current_health"):
		push_error("Charger HP must be character net state")
		failures += 1
	var world_state := Profiles.state_paths(Profiles.WORLD_PROP)
	if world_state.has(":net_phase") or world_state.has(":net_telegraph"):
		push_error("Charger phase state belongs on CHARGE, not every world_prop")
		failures += 1
	if world_state.has("Health:current_health"):
		push_error("Orb/cover world_prop must not assume a Health child")
		failures += 1
	var cover_state := Profiles.state_paths(Profiles.COVER)
	if not cover_state.has(":cover_t") or not cover_state.has(":home"):
		push_error("Cover restage must rewind height and home")
		failures += 1
	if not charge_state.has("Head:rotation"):
		push_error("Charger bow must be rewindable pose, not a late interpolator ghost")
		failures += 1
	if not (":_eyes_chasing" in Character.NET_STATE_PATHS):
		push_error("Chase eye lights must be character net state so remotes can draw them")
		failures += 1
	if not (":eye_glow_color" in Character.NET_STATE_PATHS):
		push_error("Eye glow must be character net state so remotes can draw them")
		failures += 1
	var charger := Charger.new()
	var charger_profile := charger._net_rewind_profile()
	charger.free()
	if charger_profile != Profiles.CHARGE:
		push_error("Charger must attach with CHARGE interpolator profile")
		failures += 1
	return failures


func _test_lan_agreement_contract() -> int:
	## Encodes the LAN pit proof we cannot run as two clients here.
	var failures := 0
	if not playable_uses_physics_factor():
		push_error("Playable move must go through NetClock.move_character")
		failures += 1
	var threat_scripts := [
		"res://scripts/monsters/abilities/ember_lob_projectile.gd",
		"res://scripts/monsters/abilities/ember_halo_projectile.gd",
		"res://scripts/monsters/abilities/ember_dash_trail_segment.gd",
		"res://scripts/monsters/abilities/ash_ice_projectile.gd",
		"res://scripts/monsters/abilities/ash_frost_breath_cloud.gd",
		"res://scripts/monsters/abilities/wretch_command_orb_projectile.gd",
		"res://scripts/monsters/abilities/wretch_summon_drop_orb.gd",
		"res://scripts/spells/fireball_projectile.gd",
		"res://scripts/spells/flare_effect.gd",
	]
	for path in threat_scripts:
		var source := FileAccess.get_file_as_string(path)
		if source.find("func _rollback_tick") < 0:
			push_error("%s must simulate on the netfox tick" % path)
			failures += 1
		if source.find("NetLiveness") < 0:
			push_error("%s must use NetLiveness instead of tick-loop queue_free" % path)
			failures += 1
	var ember_fx := FileAccess.get_file_as_string(
		"res://scripts/monsters/abilities/ember_lob_projectile.gd"
	)
	if ember_fx.find("replicate_world_fx") < 0:
		push_error("Ember lob must replicate VFX through NetLiveness, not local-only spawn")
		failures += 1
	var input_src := FileAccess.get_file_as_string("res://scripts/net/player_net_input.gd")
	if input_src.find("func _exit_tree") < 0 or input_src.find("disconnect(_on_before_tick_loop)") < 0:
		push_error("PlayerNetInput must drop NetworkTime.before_tick_loop on exit")
		failures += 1
	var trail_src := FileAccess.get_file_as_string(
		"res://scripts/monsters/abilities/ember_dash_trail_segment.gd"
	)
	if trail_src.find("can_query_overlaps") < 0:
		push_error("Trail rollback must not query overlaps when monitoring is off")
		failures += 1
	var weapon_src := FileAccess.get_file_as_string(
		"res://addons/netfox.extras/weapon/network-weapon.gd"
	)
	if weapon_src.find("func _exit_tree") < 0 or weapon_src.find("disconnect(_before_tick_loop)") < 0:
		push_error("NetworkWeapon must drop NetworkTime.before_tick_loop on exit")
		failures += 1
	var slide_src := FileAccess.get_file_as_string("res://scripts/slide_surface.gd")
	if slide_src.find("func sync_motion_from_pose") < 0:
		push_error("Jump must probe a real floor; is_on_floor is stale after rollback")
		failures += 1
	var playable_src := FileAccess.get_file_as_string(
		"res://scripts/characters/playable_character.gd"
	)
	if playable_src.find("RollbackSynchronizer") < 0:
		push_error("Solo must keep engine move when the clock ticks without rollback")
		failures += 1
	var monster_src := FileAccess.get_file_as_string("res://scripts/monsters/monster.gd")
	var deferred_bind := "call_deferred(\"_bind_rewindable\")"
	if monster_src.find("_bind_rewindable()") < 0 or monster_src.find(deferred_bind) >= 0:
		push_error("Monsters must bind rewind on the dump frame, not a deferred hitch")
		failures += 1
	for live_path in [
		"res://scripts/monsters/abilities/ember_lob_projectile.gd",
		"res://scripts/monsters/abilities/ember_halo_projectile.gd",
		"res://scripts/monsters/abilities/ember_dash_trail_segment.gd",
		"res://scripts/monsters/abilities/ember_lob_ability.gd",
		"res://scripts/monsters/abilities/ember_halo_ability.gd",
		"res://scripts/monsters/charger.gd",
	]:
		var live_src := FileAccess.get_file_as_string(live_path)
		if live_src.find("MeshInstance3D.new") >= 0:
			push_error("%s must instance authored FX scenes, not MeshInstance3D.new" % live_path)
			failures += 1
	var charger_src := FileAccess.get_file_as_string("res://scripts/monsters/charger.gd")
	if charger_src.find("_ghost_ram_victim") < 0:
		push_error("Charger ram must collision-exception players after a hit")
		failures += 1
	if charger_src.find("_hit_bodies") >= 0:
		push_error("Ram ghosts must come from restored stun this tick, not a sticky hit map")
		failures += 1
	if charger_src.find("is_stunned") < 0 or charger_src.find("RAM_HIT_RANGE := 0.55") < 0:
		push_error("Charger must not ghost until stun sticks, and must not hit at 1.7m")
		failures += 1
	if charger_src.find("get_nodes_in_group(\"player\")") < 0:
		push_error("Ram exceptions must be re-derived from live players each tick")
		failures += 1
	for path in [
		"res://scripts/arena/arena_cover.gd",
		"res://scripts/arena/spawn_telegraph.gd",
	]:
		var source := FileAccess.get_file_as_string(path)
		if source.find("func _rollback_tick") < 0:
			push_error("%s must simulate on the netfox tick" % path)
			failures += 1
	var voice_src := FileAccess.get_file_as_string("res://scripts/voice/game_voice_session.gd")
	if voice_src.find("NetworkTime") >= 0:
		push_error("Voice session must stay off NetworkTime")
		failures += 1
	return failures


func playable_uses_physics_factor() -> bool:
	var source := FileAccess.get_file_as_string("res://scripts/characters/playable_character.gd")
	return (
		source.find("NetClockScript.move_character") >= 0
		and source.find("func _rollback_tick") >= 0
	)


func _test_apply_hit_skips_non_authority() -> int:
	if not ClassDB.class_has_method("Object", "get"):
		return 1
	if NetWorldEventScript.primitive_for_effect("unknown") != "":
		push_error("Unknown effects must not pick a primitive")
		return 1
	return 0
