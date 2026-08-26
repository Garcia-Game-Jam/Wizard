extends Node3D

## Greybox pit match: spawn players, dump encounters, grant a spell every third fight.

enum Staging { NONE, COVER, SPOTLIGHT }

const ArenaRunScript := preload("res://scripts/arena/arena_run.gd")
const ArenaEncountersScript := preload("res://scripts/arena/arena_encounters.gd")
const NetWorldEventScript := preload("res://scripts/net/net_world_event.gd")
const NetLivenessScript := preload("res://scripts/net/net_liveness.gd")
const Profiles := preload("res://scripts/net/net_rewindable_profiles.gd")
const NetClockScript := preload("res://scripts/net/net_clock.gd")

const FIRST_FIGHT_DELAY_SEC := 0.5
const COVER_MOVE_SEC := 1.7
const SPOTLIGHT_SEC := 3.0
const RESPAWN_SEC := 2.0
const PATROL_SIZE := Vector2(40.0, 28.0)
const ROLLBACK_WIDE_TICKS := 8

var _run: ArenaRun
var _local_player: CharacterBody3D
var _wave_live := false
var _between_timer := 0.0
var _pending_respawns: Dictionary = {}
var _staging: Staging = Staging.NONE
var _staging_timer := 0.0
var _pending_encounter := 0
var _cover_misses := 0

@onready var players_root: Node3D = $Players
@onready var monsters_root: Node3D = $Monsters
@onready var pads_root: Node3D = $Pads
@onready var cover_root: Node3D = $Cover
@onready var spawn_telegraph: Node3D = $SpawnTelegraph
@onready var spell_registry: SpellRegistry = $SpellRegistry
@onready var game_hud: CanvasLayer = $GameHUD
@onready var voice_validator: VoiceSpellValidator = $VoiceSpellValidator
@onready var pause_menu: PauseMenu = $PauseMenu


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	_run = ArenaRunScript.create(ArenaEncountersScript.UNLOCK_QUEUE)
	pause_menu.quit_to_menu_requested.connect(_on_quit_to_menu)
	if voice_validator != null:
		voice_validator.apply_settings_from_manager()
	SettingsManager.settings_applied.connect(_on_voice_settings_applied)

	TrailRegistry.reset()
	await voice_validator.prepare_for_match()
	SteamProximityVoiceHub.set_mode(SteamProximityVoiceHub.Mode.GAME)

	NetworkManager.spawn_players(players_root, _configure_local_player)
	await NetworkManager.players_spawned
	_place_players_at_spawns()
	if GameState.is_multiplayer:
		await NetClockScript.start_for_match()
	_bind_cover()
	_bind_telegraph()
	_bind_player_deaths()
	_refresh_hud_prompt()

	if GameState.is_multiplayer:
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		NetworkManager.sync_match_phase(MatchState.Phase.ACTIVE)

	if _is_run_host():
		_between_timer = FIRST_FIGHT_DELAY_SEC


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _is_run_host():
		return
	if _staging != Staging.NONE:
		_tick_staging(delta)
		return
	if _between_timer > 0.0:
		_between_timer -= delta
		if _between_timer <= 0.0:
			_host_begin_staging()
		return
	if _wave_live and _live_monster_count() == 0:
		_host_resolve_fight()


func _is_run_host() -> bool:
	if not GameState.is_multiplayer:
		return true
	return multiplayer.is_server()


func _authority_rpc(method: StringName, args: Array) -> void:
	if GameState.is_multiplayer:
		match args.size():
			1:
				rpc(method, args[0])
			2:
				rpc(method, args[0], args[1])
			_:
				push_error("Arena: unsupported rpc arity for %s" % method)
	else:
		callv(method, args)


func _on_voice_settings_applied() -> void:
	if voice_validator != null:
		voice_validator.apply_settings_from_manager()


func _configure_local_player(player: CharacterBody3D) -> void:
	_local_player = player
	var loadout: Node = player.get_spell_loadout()
	var casting_session: SpellCastingSession = player.get_casting_session()
	var effect_applier: Node = player.get_effect_applier()
	loadout.configure(spell_registry.get_all_spells())
	loadout.apply_starting_spells(ArenaEncountersScript.STARTER_SPELL_IDS)
	var spell_hotbar := player.get_node_or_null("%SpellHotbar")
	if spell_hotbar == null:
		spell_hotbar = player.get_node_or_null("SpellHotbar")
	_fill_starter_hotbar(spell_hotbar)
	var health := player.get_node_or_null("Health") as Health
	game_hud.configure(loadout, casting_session, spell_hotbar, health)
	var inventory := player.get_node_or_null("%PlayerInventory")
	if inventory == null:
		inventory = player.get_node_or_null("PlayerInventory")
	if inventory != null and game_hud.has_method("configure_inventory"):
		game_hud.configure_inventory(inventory)
	casting_session.configure(voice_validator, loadout)
	casting_session.add_to_group("casting_session")
	player.configure_interaction(loadout, casting_session, game_hud, effect_applier)


func apply_synced_spell_cast(caster_peer_id: int, spell_id: String, params: Dictionary) -> void:
	var player := players_root.get_node_or_null(str(caster_peer_id)) as CharacterBody3D
	if player == null:
		return
	var spell := spell_registry.get_spell(spell_id) if spell_registry != null else null
	var applier := player.get_node_or_null("%SpellEffectApplier")
	if spell != null and applier != null and applier.has_method("apply_synced_cast"):
		applier.call("apply_synced_cast", player, spell, params)
		return
	NetWorldEventScript.dispatch_spell(player, params)


func _fill_starter_hotbar(hotbar: Node) -> void:
	if hotbar == null or not hotbar.has_method("set_slot"):
		return
	var index := 0
	for spell_id in ArenaEncountersScript.STARTER_SPELL_IDS:
		if index >= 3:
			break
		hotbar.call("set_slot", index, spell_id)
		index += 1


func _on_peer_connected(peer_id: int) -> void:
	NetworkManager.spawn_player_for_peer(peer_id, players_root, _configure_local_player)
	call_deferred("_place_players_at_spawns")
	call_deferred("_bind_player_deaths")


func _on_peer_disconnected(peer_id: int) -> void:
	NetworkManager.despawn_player_for_peer(peer_id, players_root)


func _place_players_at_spawns() -> void:
	for child in players_root.get_children():
		if not (child is CharacterBody3D):
			continue
		var player := child as CharacterBody3D
		var peer_id := 1
		if player.name.is_valid_int():
			peer_id = int(player.name)
		## TickInterpolator writes display pose on this same body, so proximity
		## chat follows the interpolated wizard without putting audio on the tick.
		SteamProximityVoiceHub.set_peer_anchor(peer_id, player)
		player.global_position = _spawn_for_player(player)


func _spawn_for_player(player: Node3D) -> Vector3:
	var index := 0
	if "player_index" in player:
		index = int(player.get("player_index"))
	var marker := players_root.get_node_or_null("PlayerSpawn_%d" % index)
	if marker is Node3D:
		return (marker as Node3D).global_position
	var fallback := players_root.get_child(0)
	if fallback is Node3D and not (fallback is CharacterBody3D):
		return (fallback as Node3D).global_position
	return Vector3(0.0, 1.0, 8.0)


func _bind_player_deaths() -> void:
	for child in players_root.get_children():
		if not (child is PlayableCharacter):
			continue
		var player := child as PlayableCharacter
		var pool := player.get_node_or_null("Health") as Health
		if pool == null:
			continue
		if not pool.died.is_connected(_on_player_died):
			pool.died.connect(_on_player_died.bind(player))


func _on_player_died(_from: Variant, player: PlayableCharacter) -> void:
	var id := player.get_instance_id()
	if _pending_respawns.has(id):
		return
	_pending_respawns[id] = true
	var tree := get_tree()
	if tree == null:
		return
	tree.create_timer(RESPAWN_SEC).timeout.connect(_respawn_player.bind(player, id))


func _respawn_player(player: PlayableCharacter, id: int) -> void:
	_pending_respawns.erase(id)
	if not is_instance_valid(player) or player.is_alive():
		return
	_revive_at(player, _spawn_for_player(player))


func _host_begin_staging() -> void:
	var encounter := _run.encounter_index()
	var restage := ArenaEncountersScript.should_restage_cover(
		encounter, randf(), _cover_misses
	)
	if encounter > 0:
		if restage:
			_cover_misses = 0
		else:
			_cover_misses += 1
	_authority_rpc(&"rpc_stage_between", [encounter, restage])
	_pending_encounter = encounter
	if restage:
		_staging = Staging.COVER
		_staging_timer = COVER_MOVE_SEC
	else:
		_host_show_telegraph()


func _host_show_telegraph() -> void:
	_authority_rpc(&"rpc_show_telegraph", [_pending_encounter])
	_staging = Staging.SPOTLIGHT
	_staging_timer = SPOTLIGHT_SEC


func _tick_staging(delta: float) -> void:
	_staging_timer -= delta
	if _staging_timer > 0.0:
		return
	if _staging == Staging.COVER:
		_host_show_telegraph()
		return
	if _staging == Staging.SPOTLIGHT:
		_authority_rpc(&"rpc_begin_fight", [_pending_encounter])
		_staging = Staging.NONE


func _host_resolve_fight() -> void:
	_wave_live = false
	var granted := _run.complete_fight()
	_authority_rpc(&"rpc_fight_resolved", [_run.to_snapshot(), granted])
	_host_begin_staging()


@rpc("authority", "call_local", "reliable")
func rpc_stage_between(encounter_index: int, restage_cover: bool) -> void:
	_pending_encounter = encounter_index
	_revive_dead_players()
	if restage_cover:
		_restage_cover(encounter_index)


@rpc("authority", "call_local", "reliable")
func rpc_show_telegraph(encounter_index: int) -> void:
	if spawn_telegraph != null and spawn_telegraph.has_method("show_pads"):
		spawn_telegraph.call("show_pads", ArenaEncountersScript.pads_for(encounter_index))


@rpc("authority", "call_local", "reliable")
func rpc_begin_fight(encounter_index: int) -> void:
	_clear_monsters()
	if spawn_telegraph != null and spawn_telegraph.has_method("clear_pads"):
		spawn_telegraph.call("clear_pads")
	_spawn_dump(ArenaEncountersScript.dump_for(encounter_index))
	_wave_live = true
	_staging = Staging.NONE
	_refresh_hud_prompt()
	call_deferred("_warn_wide_rollback")


@rpc("authority", "call_local", "reliable")
func rpc_fight_resolved(snapshot: Dictionary, granted_spell_id: String) -> void:
	_wave_live = false
	_run = ArenaRunScript.from_snapshot(snapshot)
	_clear_monsters()
	if not granted_spell_id.is_empty():
		_grant_spell_to_local(granted_spell_id)
	_refresh_hud_prompt()


func _grant_spell_to_local(spell_id: String) -> void:
	if _local_player == null or not is_instance_valid(_local_player):
		return
	var loadout: Node = _local_player.get_spell_loadout()
	if loadout != null and loadout.has_method("learn_spell"):
		loadout.learn_spell(spell_id, "arena_grant")
	var def := spell_registry.get_spell(spell_id)
	var hotbar := _local_player.get_node_or_null("%SpellHotbar")
	if hotbar == null:
		hotbar = _local_player.get_node_or_null("SpellHotbar")
	if def != null and hotbar != null and hotbar.has_method("begin_pending"):
		hotbar.call("begin_pending", def)


func _revive_dead_players() -> void:
	for child in players_root.get_children():
		if not (child is PlayableCharacter):
			continue
		var player := child as PlayableCharacter
		if player.is_alive():
			continue
		_pending_respawns.erase(player.get_instance_id())
		_revive_at(player, _spawn_for_player(player))


func _revive_at(player: PlayableCharacter, world_pos: Vector3) -> void:
	if player.health != null:
		player.health.revive()
	player.restore_after_revive()
	player.global_position = world_pos
	player.velocity = Vector3.ZERO
	var ti := player.get_node_or_null("TickInterpolator")
	if ti != null and ti.has_method("teleport"):
		ti.call("teleport")


func _bind_cover() -> void:
	for child in cover_root.get_children():
		NetLivenessScript.attach(child, Profiles.COVER)


func _bind_telegraph() -> void:
	if spawn_telegraph != null:
		NetLivenessScript.attach(spawn_telegraph, Profiles.WORLD_PROP)


func _restage_cover(encounter_index: int) -> void:
	var positions := ArenaEncountersScript.cover_positions(encounter_index)
	var i := 0
	for child in cover_root.get_children():
		if i >= positions.size():
			break
		if child.has_method("restage_to"):
			child.call("restage_to", positions[i])
		i += 1


func _warn_wide_rollback() -> void:
	if not NetClockScript.is_ticking():
		return
	var tree := get_tree()
	if tree == null:
		return
	var perf := tree.root.get_node_or_null("NetworkPerformance")
	if perf == null or not perf.has_method("get_rollback_ticks"):
		return
	var ticks := int(perf.call("get_rollback_ticks"))
	if ticks > ROLLBACK_WIDE_TICKS:
		push_warning("Arena: dump resimulated %d ticks (netfox rewind)" % ticks)


func _spawn_dump(dump: Array[Dictionary]) -> void:
	for entry in dump:
		var kind := str(entry.get("kind", ""))
		var pad := int(entry.get("pad", 0))
		var path := ArenaEncountersScript.scene_path_for(kind)
		if path.is_empty() or not ResourceLoader.exists(path):
			push_warning("Arena: missing monster scene for %s" % kind)
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var monster := packed.instantiate() as Node3D
		if monster == null:
			continue
		var spawn := _pad_position(pad)
		monster.set_meta("lookdev_live_ai", true)
		monster.set_meta("patrol_home", spawn)
		monster.set_meta("patrol_size", PATROL_SIZE)
		if "lookdev_override" in monster:
			monster.set("lookdev_override", false)
		if "patrol_radius" in monster:
			monster.set("patrol_radius", 12.0)
		monsters_root.add_child(monster)
		monster.global_position = spawn
		monster.set_multiplayer_authority(1)


func _pad_position(pad: int) -> Vector3:
	var marker := pads_root.get_node_or_null("Pad%d" % pad)
	if marker is Node3D:
		return (marker as Node3D).global_position
	var count := pads_root.get_child_count()
	if count > 0:
		var child := pads_root.get_child(pad % count)
		if child is Node3D:
			return (child as Node3D).global_position
	return Vector3(0.0, 0.05, 0.0)


func _clear_monsters() -> void:
	for child in monsters_root.get_children():
		child.queue_free()


func _live_monster_count() -> int:
	var n := 0
	for child in monsters_root.get_children():
		if not is_instance_valid(child) or child.is_queued_for_deletion():
			continue
		if child is MonsterCorpse:
			continue
		if not (child is Character):
			continue
		if not (child as Character).is_alive():
			continue
		n += 1
	return n


func _refresh_hud_prompt() -> void:
	if game_hud == null or not game_hud.has_method("set_interaction_prompt"):
		return
	var fight_no := _run.completed_fights + 1
	var into := _run.fights_into_cycle()
	var until_grant := ArenaRun.FIGHTS_PER_SPELL - into
	if _run.completed_fights > 0 and into == 0:
		until_grant = ArenaRun.FIGHTS_PER_SPELL
	var grant_name := _run.next_grant_spell_id()
	if grant_name.is_empty():
		grant_name = "nothing queued"
	var line := "Fight %d  ·  %d until %s" % [fight_no, until_grant, grant_name]
	if not _run.granted_spell_ids.is_empty():
		line += "  ·  learned %s" % ", ".join(_run.granted_spell_ids)
	game_hud.call("set_interaction_prompt", line)


func _on_quit_to_menu() -> void:
	SettingsManager.stop_mic_test()
	NetworkManager.disconnect_session()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var app := get_tree().get_first_node_in_group("game_app")
	if app != null and app.has_method("return_to_main_menu"):
		app.call_deferred("return_to_main_menu")
	else:
		get_tree().call_deferred("change_scene_to_file", "res://scenes/game_app.tscn")
