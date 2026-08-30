extends Node3D

## Greybox pit match: spawn players, dump encounters, grant a spell every third fight.

enum Staging { NONE, COVER, SPOTLIGHT }

const ArenaRunScript := preload("res://scripts/arena/arena_run.gd")
const ArenaEncountersScript := preload("res://scripts/arena/arena_encounters.gd")
const NetWorldEventScript := preload("res://scripts/net/net_world_event.gd")
const NetLivenessScript := preload("res://scripts/net/net_liveness.gd")
const Profiles := preload("res://scripts/net/net_rewindable_profiles.gd")
const NetClockScript := preload("res://scripts/net/net_clock.gd")
const NetThreatFxScript := preload("res://scripts/net/net_threat_fx.gd")
const TestEnvScript := preload("res://scripts/test/test_env.gd")

const FIRST_FIGHT_DELAY_SEC := 0.5
const COVER_MOVE_SEC := 1.7
const SPOTLIGHT_SEC := 3.0
const CORPSE_BEAT_SEC := 3.0
const PATROL_SIZE := Vector2(40.0, 28.0)
const ROLLBACK_WIDE_TICKS := 8

var _run: ArenaRun
var _local_player: CharacterBody3D
var _wave_live := false
var _between_timer := 0.0
var _staging: Staging = Staging.NONE
var _staging_timer := 0.0
var _pending_encounter := 0
var _cover_misses := 0
var _dump_scenes: Dictionary = {}
var _game_over := false
var _enemies_killed := 0
var _player_deaths := 0
var _intentional_revive := false
var _corpse_beat := 0.0

@onready var players_root: Node3D = $Players
@onready var monsters_root: Node3D = $Monsters
@onready var corpses_root: Node3D = %Corpses
@onready var pads_root: Node3D = $Pads
@onready var cover_root: Node3D = $Cover
@onready var spawn_telegraph: Node3D = $SpawnTelegraph
@onready var spell_registry: SpellRegistry = $SpellRegistry
@onready var game_hud: CanvasLayer = $GameHUD
@onready var voice_validator: VoiceSpellValidator = $VoiceSpellValidator
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var game_over_overlay: CanvasLayer = $GameOverOverlay


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	_run = ArenaRunScript.create(ArenaEncountersScript.UNLOCK_QUEUE)
	## After autoloads exist. Const-preloading charger.tscn from ArenaEncounters
	## broke LAN E2E (--script parses that table before GameState).
	_warm_live_dump_scenes()
	NetDiag.begin_session({"scenario": "arena", "role": _diag_role()})
	pause_menu.quit_to_menu_requested.connect(_on_quit_to_menu)
	if game_over_overlay != null and game_over_overlay.has_signal("leave_requested"):
		game_over_overlay.connect("leave_requested", _on_quit_to_menu)
	if voice_validator != null:
		voice_validator.apply_settings_from_manager()
	SettingsManager.settings_applied.connect(_on_voice_settings_applied)

	if voice_validator != null and not TestEnvScript.skip_match_voice():
		await voice_validator.prepare_for_match()
	SteamProximityVoiceHub.set_mode(SteamProximityVoiceHub.Mode.GAME)

	NetworkManager.spawn_players(players_root, _configure_local_player)
	await NetworkManager.players_spawned
	_place_players_at_spawns()
	## Cover and telegraph already exist in the scene. Enroll them before the
	## clock so Steam guests do not get rewind for paths they have not named.
	_bind_cover()
	_bind_telegraph()
	if GameState.is_multiplayer:
		NetDiag.mark("clock_start")
		await NetClockScript.start_for_match()
		NetDiag.mark("clock_started")
	_bind_player_deaths()
	_refresh_hud_prompt()

	if GameState.is_multiplayer:
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		NetworkManager.sync_match_phase(MatchState.Phase.ACTIVE)

	if _is_run_host():
		_between_timer = FIRST_FIGHT_DELAY_SEC


func _exit_tree() -> void:
	NetDiag.end_session()


func _diag_role() -> String:
	if not GameState.is_multiplayer:
		return "solo"
	return "host" if multiplayer.is_server() else "guest"


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _is_run_host():
		return
	if _game_over:
		return
	if _has_player_pawns() and _living_player_count() == 0:
		_host_emit_game_over()
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
		_corpse_beat += delta
		if _corpse_beat >= CORPSE_BEAT_SEC:
			_host_resolve_fight()
		return
	_corpse_beat = 0.0


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
			3:
				rpc(method, args[0], args[1], args[2])
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
	game_hud.configure(loadout, casting_session, spell_hotbar, player as Character)
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
		if not (child is Player):
			continue
		var player := child as Player
		if not player.died.is_connected(_on_player_died):
			player.died.connect(_on_player_died.bind(player))
		if not player.revived.is_connected(_on_player_revived):
			player.revived.connect(_on_player_revived)


func _on_player_died(_from: Variant, player: Player) -> void:
	NetDiag.mark("player_died", player.name)
	if not _is_run_host():
		return
	_player_deaths += 1


func _on_player_revived() -> void:
	if not _is_run_host() or _intentional_revive:
		return
	_player_deaths = maxi(_player_deaths - 1, 0)


func _host_begin_staging() -> void:
	if _game_over:
		return
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
	if _game_over:
		return
	_wave_live = false
	var granted := _run.complete_fight()
	_authority_rpc(&"rpc_fight_resolved", [_run.to_snapshot(), granted])
	_host_begin_staging()


@rpc("authority", "call_local", "reliable")
func rpc_stage_between(encounter_index: int, restage_cover: bool) -> void:
	_pending_encounter = encounter_index
	_clear_stage_corpses()
	_revive_dead_players()
	if restage_cover:
		_restage_cover(encounter_index)


@rpc("authority", "call_local", "reliable")
func rpc_show_telegraph(encounter_index: int) -> void:
	if spawn_telegraph != null and spawn_telegraph.has_method("show_pads"):
		spawn_telegraph.call("show_pads", ArenaEncountersScript.pads_for(encounter_index))


@rpc("authority", "call_local", "reliable")
func rpc_begin_fight(encounter_index: int) -> void:
	if _game_over:
		return
	var t0 := Time.get_ticks_usec()
	NetDiag.mark("encounter_begin", str(encounter_index))
	_clear_monsters()
	if spawn_telegraph != null and spawn_telegraph.has_method("clear_pads"):
		spawn_telegraph.call("clear_pads")
	NetDiag.mark("dump_cleared", "%d_us" % (Time.get_ticks_usec() - t0))
	_spawn_dump(encounter_index, ArenaEncountersScript.dump_for(encounter_index))
	NetDiag.mark("dump_done", "%d %d_us" % [encounter_index, Time.get_ticks_usec() - t0])
	_wave_live = true
	_staging = Staging.NONE
	_corpse_beat = 0.0
	_refresh_hud_prompt()
	call_deferred("_warn_wide_rollback")


@rpc("authority", "call_local", "reliable")
func rpc_fight_resolved(snapshot: Dictionary, granted_spell_id: String) -> void:
	_wave_live = false
	_run = ArenaRunScript.from_snapshot(snapshot)
	if not granted_spell_id.is_empty():
		_grant_spell_to_local(granted_spell_id)
	_refresh_hud_prompt()


@rpc("authority", "call_local", "reliable")
func rpc_game_over(stages_cleared: int, enemies_killed: int, deaths: int) -> void:
	_game_over = true
	_wave_live = false
	_staging = Staging.NONE
	_between_timer = 0.0
	if game_over_overlay != null and game_over_overlay.has_method("show_run"):
		game_over_overlay.call("show_run", stages_cleared, enemies_killed, deaths)


func broadcast_threat_fx(kind: String, origin: Vector3, extra: Dictionary) -> void:
	if not GameState.is_multiplayer or not _is_run_host():
		return
	rpc_threat_fx.rpc(kind, origin, extra)


@rpc("authority", "call_remote", "reliable")
func rpc_threat_fx(kind: String, origin: Vector3, extra: Dictionary) -> void:
	NetThreatFxScript.apply(kind, origin, extra)


## Host-only door: every peer creates the same Corpses/{name}Corpse before rollback diffs.
func request_corpse_spawn(source: Node3D, hit_dir: Vector3, opts: Dictionary) -> void:
	if source == null or not is_inside_tree() or not source.is_inside_tree():
		return
	if not NetClockScript.is_session_multiplayer() or not _is_run_host():
		return
	_authority_rpc(&"rpc_spawn_corpse", [_pack_corpse_wire(source, hit_dir, opts)])


@rpc("authority", "call_local", "reliable")
func rpc_spawn_corpse(wire: Dictionary) -> void:
	_apply_corpse_spawn(wire)


func _pack_corpse_wire(source: Node3D, hit_dir: Vector3, opts: Dictionary) -> Dictionary:
	var wire := {
		"source_path": str(get_path_to(source)),
		"hit_dir_x": hit_dir.x,
		"hit_dir_y": hit_dir.y,
		"hit_dir_z": hit_dir.z,
	}
	var impulse: Vector3 = opts.get("impulse", Vector3.ZERO)
	if impulse.length_squared() > 0.0001:
		wire["impulse_x"] = impulse.x
		wire["impulse_y"] = impulse.y
		wire["impulse_z"] = impulse.z
	var carry: Vector3 = opts.get("carry", Vector3.ZERO)
	if carry.length_squared() > 0.0001:
		wire["carry_x"] = carry.x
		wire["carry_y"] = carry.y
		wire["carry_z"] = carry.z
	if opts.has("linger_sec"):
		wire["linger_sec"] = float(opts["linger_sec"])
	if opts.has("fade_sec"):
		wire["fade_sec"] = float(opts["fade_sec"])
	if bool(opts.get("reparent", false)):
		wire["reparent"] = true
	return wire


func _apply_corpse_spawn(wire: Dictionary) -> void:
	var rel := str(wire.get("source_path", ""))
	if rel.is_empty():
		return
	var source := get_node_or_null(rel) as Node3D
	if source == null:
		return
	var character := source as Character
	if character != null and is_instance_valid(character.death_corpse):
		return
	var hit_dir := Vector3(
		float(wire.get("hit_dir_x", 0.0)),
		float(wire.get("hit_dir_y", 0.0)),
		float(wire.get("hit_dir_z", 0.0))
	)
	var opts := {}
	if wire.has("impulse_x"):
		opts["impulse"] = Vector3(
			float(wire.get("impulse_x", 0.0)),
			float(wire.get("impulse_y", 0.0)),
			float(wire.get("impulse_z", 0.0))
		)
	if wire.has("carry_x"):
		opts["carry"] = Vector3(
			float(wire.get("carry_x", 0.0)),
			float(wire.get("carry_y", 0.0)),
			float(wire.get("carry_z", 0.0))
		)
	if wire.has("linger_sec"):
		opts["linger_sec"] = float(wire["linger_sec"])
	if wire.has("fade_sec"):
		opts["fade_sec"] = float(wire["fade_sec"])
	if bool(wire.get("reparent", false)):
		opts["reparent"] = true
	var corpse := Corpse.spawn(source, hit_dir, opts)
	if character != null:
		character.death_corpse = corpse


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
	_intentional_revive = true
	for child in players_root.get_children():
		if not (child is Player):
			continue
		var player := child as Player
		if player.is_alive() and not player.is_death_physics():
			continue
		_revive_at(player, _spawn_for_player(player))
	_intentional_revive = false


func _clear_stage_corpses() -> void:
	if corpses_root == null:
		return
	for child in corpses_root.get_children():
		if child is Corpse:
			(child as Corpse).despawn()


func _revive_at(player: Player, world_pos: Vector3) -> void:
	NetDiag.mark("respawn", player.name)
	player.queue_pad_rez(world_pos)


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
	NetDiag.mark("dump_rewind", str(ticks))
	if ticks > ROLLBACK_WIDE_TICKS:
		push_warning("Arena: dump resimulated %d ticks (netfox rewind)" % ticks)


func _warm_live_dump_scenes() -> void:
	for kind in [ArenaEncountersScript.KIND_CHARGER, ArenaEncountersScript.KIND_EMBER]:
		var packed := ArenaEncountersScript.packed_scene_for(kind)
		if packed != null:
			_dump_scenes[kind] = packed


func _dump_packed_scene(kind: String) -> PackedScene:
	var held: Variant = _dump_scenes.get(kind)
	if held is PackedScene:
		return held
	return ArenaEncountersScript.packed_scene_for(kind)


func _spawn_dump(encounter_index: int, dump: Array[Dictionary]) -> void:
	var slot := 0
	for entry in dump:
		var kind := str(entry.get("kind", ""))
		var pad := int(entry.get("pad", 0))
		var t_load := Time.get_ticks_usec()
		var packed := _dump_packed_scene(kind)
		var load_us := Time.get_ticks_usec() - t_load
		if packed == null:
			push_warning("Arena: missing monster scene for %s" % kind)
			continue
		var t_inst := Time.get_ticks_usec()
		var monster := packed.instantiate() as Node3D
		if monster == null:
			continue
		var spawn := _pad_position(pad)
		monster.name = ArenaEncountersScript.dump_node_name(encounter_index, slot)
		monster.set_meta("lookdev_live_ai", true)
		monster.set_meta("patrol_home", spawn)
		monster.set_meta("patrol_size", PATROL_SIZE)
		if "lookdev_override" in monster:
			monster.set("lookdev_override", false)
		if "patrol_radius" in monster:
			monster.set("patrol_radius", 12.0)
		monsters_root.add_child(monster)
		monster.global_position = spawn
		monster.rotation = Vector3.ZERO
		monster.set_multiplayer_authority(1)
		if monster is Character:
			var body := monster as Character
			body.current_health = body.max_health
		var inst_us := Time.get_ticks_usec() - t_inst
		## _ready enrolled rewind at the scene origin. Seed history at the pad.
		var t_enroll := Time.get_ticks_usec()
		NetLivenessScript.commit_pose(monster)
		_bind_dump_monster(monster)
		NetDiag.mark("dump_spawn", "%s load=%d inst=%d enroll=%d" % [
			kind, load_us, inst_us, Time.get_ticks_usec() - t_enroll,
		])
		slot += 1


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
	var children := monsters_root.get_children()
	for child in children:
		monsters_root.remove_child(child)
		child.queue_free()


func _live_monster_count() -> int:
	var n := 0
	for child in monsters_root.get_children():
		if not is_instance_valid(child) or child.is_queued_for_deletion():
			continue
		if child is Corpse:
			continue
		if not (child is Character):
			continue
		if not (child as Character).is_alive():
			continue
		n += 1
	return n


func _has_player_pawns() -> bool:
	for child in players_root.get_children():
		if child is Player:
			return true
	return false


func _living_player_count() -> int:
	var n := 0
	for child in players_root.get_children():
		if child is Player and (child as Player).is_alive():
			n += 1
	return n


func _bind_dump_monster(monster: Node) -> void:
	if not (monster is Monster):
		return
	var dump := monster as Monster
	if not dump.died.is_connected(_on_dump_monster_died):
		dump.died.connect(_on_dump_monster_died)
	if not dump.revived.is_connected(_on_dump_monster_revived):
		dump.revived.connect(_on_dump_monster_revived)


func _on_dump_monster_died(_from: Variant) -> void:
	if not _is_run_host():
		return
	_enemies_killed += 1


func _on_dump_monster_revived() -> void:
	if not _is_run_host():
		return
	_enemies_killed = maxi(_enemies_killed - 1, 0)


func _host_emit_game_over() -> void:
	if _game_over:
		return
	_authority_rpc(&"rpc_game_over", [
		_run.completed_fights, _enemies_killed, _player_deaths
	])


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
	if get_tree() != null:
		get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	NetworkManager.end_match_to_menu()
	if get_tree().get_first_node_in_group("game_app") == null:
		get_tree().call_deferred("change_scene_to_file", "res://scenes/game_app.tscn")
