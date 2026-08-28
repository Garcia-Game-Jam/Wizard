class_name Player
extends Character

const DEFAULT_WALK_SPEED := 5.0
const DEFAULT_MOVE_FRICTION := 50.0
const WALK_SPEED := DEFAULT_WALK_SPEED
const SPRINT_SPEED := DEFAULT_WALK_SPEED
const JUMP_VELOCITY := 3.5
const MOUSE_SENSITIVITY := 0.002
const PLAYER_MIN_SEPARATION := 0.55
const AIM_RAY_LENGTH := 200.0

const NetworkManagerScript := preload("res://scripts/network/network_manager.gd")
const TargetHighlightScript := preload("res://scripts/spells/target_highlight.gd")
const SlideSurfaceScript := preload("res://scripts/slide_surface.gd")
const PlayerDashScript := preload("res://scripts/characters/player_dash.gd")
const PlayerCrouchScript := preload("res://scripts/characters/player_crouch.gd")
const PlayerPreviewScript := preload(
	"res://scripts/characters/player_preview.gd"
)
const SpellManaScript := preload("res://scripts/spells/spell_mana.gd")
const WardSlotChannelScript := preload("res://scripts/spells/ward_slot_channel.gd")
const PlayerCombatReactionsScript := preload("res://scripts/characters/player_combat_reactions.gd")
const PlayerGhostScript := preload("res://scripts/characters/player_ghost.gd")
const NetWorldEventScript := preload("res://scripts/net/net_world_event.gd")
const NetAuthorityScript := preload("res://scripts/net/net_authority.gd")

## Movement tells and stun on top of Character.NET_STATE_PATHS.
const NET_STATE_EXTRA: PackedStringArray = [
	"Head:rotation",
	"Head/CameraPivot:rotation",
	":dash_lock_remaining",
	":dash_cooldown_remaining",
	":dash_post_decay_pending",
	":net_crouching",
	":net_sliding",
	":crouch_recovery_remaining",
	":dash_slide_grace_remaining",
	":net_wand_raised",
	":net_charge_factor",
	":net_flashlight",
	"Stun:visual_active",
	"Stun:_stunned",
	"Stun:_airborne",
	"Stun:_post_land_left",
	"Stun:_launch_vel",
]

@export var player_index: int = 0
@export var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@export_group("Movement")
## Ground foot speed (WASD on floor). Scaled by spell haste/slow effects.
@export_range(1.0, 20.0, 0.1, "suffix:m/s") var move_speed: float = DEFAULT_WALK_SPEED
## Deceleration when grounded with no WASD (m/s²). Not scaled by haste/slow.
@export_range(0.1, 200.0, 0.5) var move_friction: float = DEFAULT_MOVE_FRICTION

@export_group("Air Control")
## Air-steer strength the instant you leave the ground, as a % of move_speed.
@export_range(0.0, 150.0, 1.0, "suffix:%") var air_control_start_pct: float = 90.0
## Air-steer strength floor after being airborne a while, as a % of move_speed.
@export_range(0.0, 150.0, 1.0, "suffix:%") var air_control_min_pct: float = 65.0
## How many percentage points of air-steer strength are lost per second airborne.
@export_range(0.0, 50.0, 0.5, "suffix:%/s") var air_control_decay_pct_per_sec: float = 7.5

@export_group("Dash")
## Tuning reference only — not applied by code. Match dash_speed × dash_duration for ~this far.
@export_range(0.5, 24.0, 0.1, "suffix:m") var dash_distance: float = 3.0
## Seconds walk input is locked after a dash; velocity stays at dash_speed for this window.
@export_range(0.05, 1.0, 0.01, "suffix:s") var dash_duration: float = 0.15
## Seconds before Shift can dash again (still requires a held move direction).
@export_range(0.5, 30.0, 0.1, "suffix:s") var dash_cooldown_sec: float = 3.0
## Horizontal speed set instantly on dash (Shift + direction). Works on ground and in air.
@export_range(1.0, 40.0, 0.5, "suffix:m/s") var dash_speed: float = 20.0
## Once the dash lock ends, leftover speed quickly bleeds down to this — a %
## of move_speed. 100% = normal run speed; below 100% settles slower than
## walking, above 100% keeps some of the burst.
@export_range(25.0, 200.0, 1.0, "suffix:%") var dash_post_speed_pct: float = 100.0

@export_group("Crouch")
## Max foot speed while holding C on the ground. Also caps steering during a crouch slide.
@export_range(0.5, 10.0, 0.1, "suffix:m/s") var crouch_speed: float = 2.5
## Start a crouch slide when horizontal speed exceeds this (m/s). Not scaled by haste.
@export_range(0.0, 10.0, 0.05, "suffix:m/s") var crouch_slide_threshold: float = 0.5
## End the slide below this speed, then recovery eases into crouch walk.
@export_range(0.0, 10.0, 0.05, "suffix:m/s") var crouch_slide_exit_speed: float = 1.0
## After a dash, crouch within dash duration + this grace still starts a slide above exit speed.
@export_range(0.0, 2.0, 0.01, "suffix:s") var crouch_slide_dash_grace_sec: float = 0.6
## After slide ends, blend back to normal crouch movement for this long (or until slow enough).
@export_range(0.0, 1.5, 0.01, "suffix:s") var crouch_slide_recovery_sec: float = 0.3
## Slide friction at high speed (0–100 % of move_friction). Lower = longer dash-slide carry.
@export_range(0.0, 100.0, 1.0) var crouch_slide_friction_start: float = 12.0
## Slide friction near exit speed (0–100). Higher = snappier finish before recovery.
@export_range(0.0, 100.0, 1.0) var crouch_slide_friction: float = 35.0

var owner_peer_id: int = 0
var dash_lock_remaining: float = 0.0
var dash_cooldown_remaining: float = 0.0
var dash_post_decay_pending: bool = false
var net_crouching: bool = false
var net_sliding: bool = false
var crouch_recovery_remaining: float = 0.0
var dash_slide_grace_remaining: float = 0.0
var net_wand_raised: bool = false
var net_charge_factor: float = 0.0
var net_flashlight: bool = false
var player_corpse: MonsterCorpse = null
var saved_collision_layer: int = 1

var _spell_loadout: Node
var _casting_session: SpellCastingSession
var _game_hud: CanvasLayer
var _effect_applier: Node
var _armed_spell: SpellDefinition
var _mana: float = SpellManaScript.MANA_MAX
var _haste_aura: OmniLight3D
var _wand: PlayerWand
var _wand_raised := false
var _spell_fire_charging := false
var _spell_fire_releasing := false
var _spell_fire_slot := -1
var _spell_fire_cancel_token := 0
var _ward_channel: RefCounted = WardSlotChannelScript.new()
var _pad_rez_pos: Vector3 = Vector3.ZERO
var _pad_rez_pending: bool = false

@onready var camera_pivot: Node3D = %CameraPivot
@onready var spell_loadout: Node = %CharacterSpellLoadout
@onready var spell_hotbar: Node = %SpellHotbar
@onready var casting_session: SpellCastingSession = %SpellCastingSession
@onready var effect_applier: Node = %SpellEffectApplier
@onready var _view_camera: Camera3D = %FirstPersonCamera


func _ready() -> void:
	super._ready()
	if PlayerPreviewScript.should_use_preview_mode(self):
		PlayerPreviewScript.enter_editor_preview_mode(self)
		return

	add_to_group("player")
	collision_layer = 1
	floor_block_on_wall = false
	floor_snap_length = 0.15
	safe_margin = 0.04
	_wand = get_node_or_null("Head/CameraPivot/Wand") as PlayerWand
	if _wand == null:
		_wand = get_node_or_null("Head/CameraPivot/FirstPersonCamera/Wand") as PlayerWand
	if _wand != null:
		_wand.cache_idle_transform()
	_apply_character_color(GameState.get_player_color(player_index))
	_setup_view_camera()
	_bind_rewindable()


func _exit_tree() -> void:
	NetworkManagerScript.disable_player_sync(self)


func _death_should_tumble() -> bool:
	return false


func _death_uses_capsule_limp() -> bool:
	return false


func _on_death(_from: Node3D) -> void:
	PlayerGhostScript.enter(self)
	if _wand_raised:
		_lower_wand(true)
	_cancel_spell_fire_charge(true)


func _on_stop_death_physics() -> void:
	PlayerGhostScript.exit(self)


## Stage clear. Apply on the movement tick so HP is full before a death-ragdoll
## can spawn at the pad. Solo has no tick loop — stand up now.
func queue_pad_rez(world_pos: Vector3) -> void:
	_pad_rez_pos = world_pos
	_pad_rez_pending = true
	if not NetClockScript.is_ticking():
		_stand_up_at_pad(true)


func _stand_up_at_pad(is_fresh: bool) -> void:
	if not _pad_rez_pending:
		return
	if is_alive() and not is_death_physics():
		if is_fresh:
			_pad_rez_pending = false
		return
	global_position = _pad_rez_pos
	velocity = Vector3.ZERO
	revive()
	restore_after_revive()
	if is_fresh:
		_pad_rez_pending = false
		NetLiveness.commit_pose(self)


func _setup_view_camera() -> void:
	var local_view := _uses_local_view()
	if local_view:
		_view_camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		_view_camera.queue_free()
	var local_peer := 0
	if _multiplayer_peer_active():
		local_peer = multiplayer.get_unique_id()
	TomeDebug.log(
		"Player",
		"'%s' view=%s authority=%d local_peer=%d"
		% [
			name,
			"local" if local_view else "remote",
			get_multiplayer_authority(),
			local_peer,
		]
	)


func _uses_local_view() -> bool:
	return is_local_owner()


func _net_state_extra() -> PackedStringArray:
	return NET_STATE_EXTRA


func is_local_owner() -> bool:
	if owner_peer_id <= 0 and name.is_valid_int():
		owner_peer_id = int(name)
	if owner_peer_id > 0:
		var unique := 1
		if is_inside_tree() and multiplayer != null:
			unique = multiplayer.get_unique_id()
		return owner_peer_id == unique
	if not GameState.is_multiplayer:
		return true
	if not _multiplayer_peer_active():
		return true
	return owner_peer_id == multiplayer.get_unique_id()


func is_wand_raised() -> bool:
	return _wand_raised


func _get_net_input() -> Object:
	return get_node_or_null("Input")


func _bind_rewindable() -> void:
	if Engine.is_editor_hint():
		return
	if PlayerPreviewScript.should_use_preview_mode(self):
		return
	if not GameState.is_multiplayer and owner_peer_id <= 0:
		return
	if owner_peer_id <= 0 and name.is_valid_int():
		owner_peer_id = int(name)
	if owner_peer_id <= 0 and _multiplayer_peer_active():
		owner_peer_id = multiplayer.get_unique_id()
	NetWorldEventScript.bind_player(self, owner_peer_id, is_local_owner())


func _multiplayer_peer_active() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return false
	var peer := multiplayer.multiplayer_peer
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func initialize_player(index: int) -> void:
	player_index = index
	_apply_character_color(GameState.get_player_color(player_index))


func configure_interaction(
	spell_loadout_ref: Node,
	casting_session_ref: SpellCastingSession,
	game_hud: CanvasLayer,
	effect_applier_ref: Node
) -> void:
	_spell_loadout = spell_loadout_ref
	_casting_session = casting_session_ref
	_game_hud = game_hud
	_effect_applier = effect_applier_ref
	if _casting_session != null:
		if not _casting_session.state_changed.is_connected(_on_cast_session_state_changed):
			_casting_session.state_changed.connect(_on_cast_session_state_changed)
		if not _casting_session.listen_level_changed.is_connected(_on_cast_listen_level_changed):
			_casting_session.listen_level_changed.connect(_on_cast_listen_level_changed)
		if not _casting_session.cast_succeeded.is_connected(_on_wand_cast_succeeded):
			_casting_session.cast_succeeded.connect(_on_wand_cast_succeeded)
		if not _casting_session.cast_failed.is_connected(_on_wand_cast_failed):
			_casting_session.cast_failed.connect(_on_wand_cast_failed)
		if not _casting_session.spell_selected.is_connected(_on_wand_spell_selected):
			_casting_session.spell_selected.connect(_on_wand_spell_selected)


func get_spell_loadout() -> Node:
	return spell_loadout


func get_casting_session() -> SpellCastingSession:
	return casting_session


func get_effect_applier() -> Node:
	return effect_applier


func _monster_book() -> Node:
	return get_node_or_null("MonsterBook")


func _is_monster_book_busy() -> bool:
	var book := _monster_book()
	return book != null and book.has_method("is_busy") and bool(book.call("is_busy"))


func _is_spellbook_open() -> bool:
	return (
		_game_hud != null
		and _game_hud.has_method("is_spellbook_open")
		and bool(_game_hud.call("is_spellbook_open"))
	)


func _is_player_menu_open() -> bool:
	return (
		_game_hud != null
		and _game_hud.has_method("is_player_menu_open")
		and bool(_game_hud.call("is_player_menu_open"))
	)


func _wand_controls_blocked() -> bool:
	return (
		is_dead()
		or is_stunned()
		or _is_spellbook_open()
		or _is_player_menu_open()
		or _is_monster_book_busy()
		or get_tree().paused
	)


func is_stunned() -> bool:
	var stun := get_node_or_null("Stun")
	return stun != null and stun.has_method("is_stunned") and bool(stun.call("is_stunned"))


func apply_speed_boost(duration: float, multiplier: float) -> void:
	super.apply_speed_boost(duration, multiplier)
	_sync_haste_visual()


func _sync_haste_visual() -> void:
	var boosting := _speed_boost_timer > 0.0 and _speed_boost_multiplier > 1.01
	if not boosting:
		if _haste_aura != null:
			_haste_aura.visible = false
		return
	if _haste_aura == null:
		_haste_aura = OmniLight3D.new()
		_haste_aura.name = "HasteAura"
		_haste_aura.light_color = Color(1.0, 0.82, 0.32)
		_haste_aura.omni_range = 2.6
		_haste_aura.shadow_enabled = false
		_haste_aura.light_volumetric_fog_energy = 0.0
		_haste_aura.position = Vector3(0.0, 1.15, 0.0)
		add_child(_haste_aura)
	_haste_aura.visible = true
	_haste_aura.light_energy = 0.22 + 0.55 * clampf(_speed_boost_timer / 0.5, 0.0, 1.0)


func apply_ember_trail_burn(dps: float, slow_multiplier: float, refresh_sec: float) -> void:
	var payload := CombatPayload.new()
	payload.effects.append(Burn.with(dps, refresh_sec))
	payload.effects.append(Speed.with(slow_multiplier, refresh_sec))
	apply(self, payload)


func set_flashlight_enabled(active: bool) -> void:
	net_flashlight = active
	if _wand != null:
		_wand.set_flashlight_enabled(active)


func is_flashlight_enabled() -> bool:
	if _wand == null:
		return false
	return _wand.is_flashlight_active()


func toggle_flashlight() -> void:
	set_flashlight_enabled(not is_flashlight_enabled())


func set_flame_glow_enabled(active: bool) -> void:
	if _wand != null:
		_wand.set_flame_glow_enabled(active)


func get_wand_cast_origin() -> Vector3:
	if _wand != null:
		return _wand.get_cast_origin()
	return _head_aim_origin()


func get_wand_cast_direction() -> Vector3:
	return _aim_direction_from_origin(get_wand_cast_origin())


func get_view_camera() -> Camera3D:
	return _view_camera


func get_view_direction() -> Vector3:
	return _camera_aim_direction()


func get_view_origin() -> Vector3:
	if _view_camera != null:
		return _view_camera.global_position
	return head.global_position


func _camera_aim_direction() -> Vector3:
	return -camera_pivot.global_transform.basis.z.normalized()


func _head_aim_origin() -> Vector3:
	return head.global_position + _camera_aim_direction() * 0.6 + Vector3(0.0, 0.1, 0.0)


func _aim_direction_from_origin(origin: Vector3) -> Vector3:
	var to_aim := _crosshair_world_point() - origin
	if to_aim.length_squared() < 0.0001:
		return _camera_aim_direction()
	return to_aim.normalized()


func _crosshair_world_point() -> Vector3:
	var look := _camera_aim_direction()
	var cam_origin := get_view_origin()
	var far_point := cam_origin + look * AIM_RAY_LENGTH
	var world_3d := get_world_3d()
	if world_3d == null or world_3d.direct_space_state == null:
		return far_point
	var ray := PhysicsRayQueryParameters3D.create(cam_origin, far_point)
	ray.collide_with_areas = false
	ray.exclude = [get_rid()]
	var hit := world_3d.direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return far_point
	return hit.position


func _input(event: InputEvent) -> void:
	if not _uses_local_view():
		return
	if event.is_action_pressed("ui_cancel") and _wand_raised and not _wand_controls_blocked():
		_lower_wand(true)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not _uses_local_view():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		head.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera_pivot.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera_pivot.rotation.x = clampf(
			camera_pivot.rotation.x,
			deg_to_rad(-70.0),
			deg_to_rad(70.0)
		)
		_sync_body_yaw_to_head()

	if event.is_action_pressed("spellbook"):
		if _casting_session != null \
				and (_casting_session.is_active() or _casting_session.is_tome_teaching()):
			return
		if _game_hud != null and _game_hud.has_method("toggle_spellbook"):
			_game_hud.toggle_spellbook()

	if event.is_action_pressed("interact"):
		_try_interact()

	if event.is_action_pressed("spell_capture"):
		if _try_toggle_wand_raise():
			get_viewport().set_input_as_handled()
		return


func _on_cast_session_state_changed(state: String, _spell: SpellDefinition) -> void:
	if _wand == null:
		return
	var tip_armed := (
		_wand_raised
		and (
			state == SpellCastingSession.STATE_ARMING
			or state == SpellCastingSession.STATE_LISTENING
			or state == SpellCastingSession.STATE_VALIDATING
		)
	)
	_wand.set_armed(tip_armed)


func _on_cast_listen_level_changed(level: float) -> void:
	if _wand != null:
		_wand.set_listen_level(level)


func _on_wand_spell_selected(spell: SpellDefinition) -> void:
	if _game_hud != null and _game_hud.has_method("reveal_cast_spell"):
		_game_hud.call("reveal_cast_spell", spell)
	if _wand != null and _wand.has_method("play_spell_recognition"):
		await _wand.play_spell_recognition(spell)
	if not is_instance_valid(self):
		return
	## Slot assign already lowered the wand so LMB is free; skip the leftover flourish.
	if not _wand_raised:
		return
	_lower_wand(false)
	if _wand != null:
		_wand.play_cast_success(spell, true)


func _arm_slotted_spell(spell: SpellDefinition) -> void:
	## Kept for stun/cancel callers; slots no longer stay loaded on a timer.
	if spell == null:
		_cancel_slot_cast()


func _cancel_slot_cast() -> void:
	_cancel_spell_fire_charge(true)
	_armed_spell = null
	_spell_fire_slot = -1
	_sync_mana_hud()


func _on_wand_cast_succeeded(
	spell: SpellDefinition,
	mode: String,
	_validation: CastValidationResult
) -> void:
	if _wand == null or mode != "cast":
		return
	_wand.play_cast_success(spell)


func _on_wand_cast_failed(
	_spell: SpellDefinition,
	_reason: String,
	_partial: CastValidationResult
) -> void:
	if _wand == null or _casting_session == null:
		return
	if _casting_session.is_tome_teaching():
		return
	if _casting_session.is_wand_voice_select() and _wand_raised:
		return
	_wand.play_fizzle()


func _separate_from_players() -> void:
	for node in get_tree().get_nodes_in_group("player"):
		if node == self or not node is CharacterBody3D:
			continue

		var other: CharacterBody3D = node as CharacterBody3D
		var away: Vector3 = global_position - other.global_position
		away.y = 0.0
		if away.length_squared() < 0.0001:
			away = Vector3(1.0, 0.0, 0.0)
		var distance: float = away.length()
		if distance >= PLAYER_MIN_SEPARATION:
			continue
		global_position += away.normalized() * (PLAYER_MIN_SEPARATION - distance)


func _try_interact() -> void:
	if _casting_session != null and _casting_session.is_active():
		return


func _try_toggle_wand_raise() -> bool:
	if not _uses_local_view():
		return false
	if _wand_controls_blocked():
		return false
	if _casting_session != null and _casting_session.is_tome_teaching():
		return false
	if _wand_raised:
		_lower_wand(true)
		return true
	return _raise_wand_and_listen()


func _raise_wand_and_listen() -> bool:
	if _spell_loadout == null or _casting_session == null:
		return false
	var candidates: Array[SpellDefinition] = _filter_free_cast_candidates(
		_spell_loadout.get_known_spells()
	)
	if candidates.is_empty():
		return false
	_cancel_spell_fire_charge(true)
	_wand_raised = true
	net_wand_raised = true
	if _wand != null:
		_wand.set_raised(true)
		_wand.set_armed(true)
	_casting_session.start_wand_voice_select(candidates)
	return true

func _lower_wand(cancel_listen: bool) -> void:
	_wand_raised = false
	net_wand_raised = false
	if cancel_listen and _casting_session != null and _casting_session.is_wand_voice_select():
		_casting_session.cancel()
	if _wand != null:
		_wand.set_raised(false)
		_wand.set_armed(false)


func _can_fire_slotted_spell(spell: SpellDefinition) -> bool:
	if not (
		_uses_local_view()
		and not _wand_controls_blocked()
		and not _wand_raised
		and spell != null
		and _effect_applier != null
		and (_casting_session == null or not _casting_session.is_tome_teaching())
	):
		return false
	var one: Array[SpellDefinition] = []
	one.append(spell)
	return not _filter_free_cast_candidates(one).is_empty()


func _try_begin_slot_fire(slot_index: int) -> bool:
	if _spell_fire_charging or _spell_fire_releasing:
		return false
	if spell_hotbar == null or not spell_hotbar.has_method("get_spell_at"):
		return false
	var spell: SpellDefinition = spell_hotbar.call("get_spell_at", slot_index) as SpellDefinition
	if not _can_fire_slotted_spell(spell):
		return false
	if _wand_raised:
		_lower_wand(false)
	_armed_spell = spell
	_spell_fire_slot = slot_index
	_spell_fire_charging = true
	_refill_mana()
	if _wand != null:
		_wand.begin_cast_charge(_armed_spell)
	if _armed_spell != null and _armed_spell.effect_id == "ward":
		_ward_channel.call("begin", self)
	return true


func _try_release_slot_fire(slot_index: int) -> bool:
	if not _spell_fire_charging or slot_index != _spell_fire_slot:
		return false
	_spell_fire_charging = false
	if _wand == null or not _wand.is_cast_charge_ready():
		if _wand != null:
			_wand.fizzle_cast_charge()
		_cancel_slot_cast()
		return false
	if not _can_fire_slotted_spell(_armed_spell):
		_wand.fizzle_cast_charge()
		_cancel_slot_cast()
		return false
	_ward_channel.call("plant")
	_spell_fire_releasing = true
	_fire_armed_spell()
	return true


func _cancel_spell_fire_charge(instant: bool = false) -> void:
	if instant:
		_spell_fire_cancel_token += 1
		_spell_fire_releasing = false
	if _spell_fire_charging:
		_spell_fire_charging = false
		if _wand != null:
			_wand.cancel_cast_charge(instant)
	elif instant and _wand != null:
		_wand.cancel_cast_charge(true)
	_ward_channel.call("drop")


func consume_channel_ward() -> Node:
	if _ward_channel == null:
		return null
	return _ward_channel.call("consume") as Node


func _fire_armed_spell() -> void:
	var cost := SpellManaScript.cast_cost(_armed_spell)
	var spell := _armed_spell
	var fire_token := _spell_fire_cancel_token
	if _wand != null:
		## Flourish plays out; don't wait for the return tween before the projectile.
		_wand.return_from_cast_charge()
	if fire_token != _spell_fire_cancel_token:
		return
	if not is_instance_valid(self) or spell == null:
		_spell_fire_releasing = false
		_cancel_slot_cast()
		return
	if _armed_spell != spell:
		_spell_fire_releasing = false
		_cancel_slot_cast()
		return
	if _effect_applier.has_method("cast_spell"):
		_effect_applier.cast_spell(self, spell)
	if _spell_loadout != null and _spell_loadout.has_method("start_cooldown"):
		_spell_loadout.start_cooldown(spell.id)
	if _wand != null:
		_wand.play_cast_success(spell, true)
	_spend_mana(cost)
	_spell_fire_releasing = false
	_cancel_slot_cast()

func _refill_mana() -> void:
	_mana = SpellManaScript.MANA_MAX
	_sync_mana_hud()

func _spend_mana(amount: float) -> void:
	if amount <= 0.0:
		_sync_mana_hud()
		return
	_mana = maxf(0.0, _mana - amount)
	_sync_mana_hud()

func _sync_mana_hud() -> void:
	if _game_hud != null and _game_hud.has_method("hide_mana"):
		_game_hud.call("hide_mana")


func _filter_free_cast_candidates(known: Array[SpellDefinition]) -> Array[SpellDefinition]:
	var filtered: Array[SpellDefinition] = []
	var tree := get_tree()
	var target_active := TargetHighlightScript.has_active_highlights(tree)
	for spell in known:
		if spell == null:
			continue
		if (
			_spell_loadout != null
			and _spell_loadout.has_method("is_on_cooldown")
			and _spell_loadout.is_on_cooldown(spell.id)
		):
			continue
		match spell.id:
			"pull", "follow", "dispell":
				if not target_active:
					continue
		filtered.append(spell)
	return filtered


func _update_interaction_prompt() -> void:
	if _game_hud == null or not _game_hud.has_method("set_interaction_prompt"):
		return
	var text := _resolve_interaction_prompt()
	if spell_hotbar != null and spell_hotbar.has_method("assignment_prompt"):
		var slot_prompt := str(spell_hotbar.call("assignment_prompt"))
		if not slot_prompt.is_empty():
			text = slot_prompt
	_game_hud.set_interaction_prompt(text)


func _resolve_interaction_prompt() -> String:
	if _is_monster_book_busy():
		var book := _monster_book()
		if book != null and book.has_method("get_prompt"):
			var book_prompt := str(book.call("get_prompt"))
			if not book_prompt.is_empty():
				return book_prompt
	if _casting_session != null and _casting_session.is_active():
		return ""
	return ""


## strength_mult: 1.0 = the normal ember-halo jump pad pop; higher scales the
## apex height up (see EmberHaloFlight.jump_pad_velocity). Lets a puzzle
## Launch Trap's Trap Param tune how hard it launches the player.
func apply_ember_halo_jump_pad(strength_mult: float = 1.0) -> void:
	PlayerCombatReactionsScript.apply_ember_halo_jump_pad(self, strength_mult)


func apply_ember_halo_hit(hit_dir: Vector3) -> void:
	PlayerCombatReactionsScript.apply_ember_halo_hit(self, hit_dir)


func apply_wretch_command_hit(_hit_dir: Vector3) -> void:
	apply_speed_boost(2.0, 0.1)


func apply_rat_explode_hit(_hit_dir: Vector3) -> void:
	apply_speed_boost(0.75, 0.25)


func _physics_process(delta: float) -> void:
	if is_death_physics():
		if NetClockScript.is_ticking() and get_node_or_null("RollbackSynchronizer") != null:
			return
		PlayerGhostScript.tick(self, delta, _get_net_input())
		return
	## Clock ticking without a RollbackSynchronizer (solo, leftover sync) must
	## still simulate here — _rollback_tick never runs.
	if NetClockScript.is_ticking() and get_node_or_null("RollbackSynchronizer") != null:
		_sync_remote_tells()
		if is_local_owner():
			_update_interaction_prompt()
		return
	_simulate_move(delta, true, null)


func _rollback_tick(delta: float, _tick: int, is_fresh: bool) -> void:
	_stand_up_at_pad(is_fresh)
	if is_death_physics():
		PlayerGhostScript.tick(self, delta, _get_net_input())
		return
	var net_input := _get_net_input()
	_simulate_move(delta, is_fresh, net_input)
	if is_fresh:
		NetDiag.pawn_sample(self, is_local_owner())


func _simulate_move(delta: float, is_fresh: bool, net_input: Object) -> void:
	if net_input != null:
		_apply_net_look(net_input)
		_apply_net_tells(net_input)
	_sync_body_yaw_to_head()
	tick_speed_boost(delta)
	if is_fresh:
		_sync_haste_visual()
	if GameState.is_multiplayer and not NetAuthorityScript.should_predict_or_simulate(self):
		return
	if not is_local_owner() and net_input == null and not NetClockScript.is_ticking():
		return
	tick_burn(delta)
	if is_stunned():
		var stun := get_node("Stun")
		stun.call("tick_physics", self, delta, gravity)
		SlideSurfaceScript.prepare(self)
		NetClockScript.move_character(self)
		stun.call("after_slide", self)
		_separate_from_players()
		if is_fresh and is_local_owner():
			_update_interaction_prompt()
		return

	PlayerDashScript.tick_and_try(self, head, delta, {}, net_input)
	PlayerDashScript.tick_post_decay(self, delta)
	PlayerCrouchScript.tick(self, net_input, delta)
	var dash_active := PlayerDashScript.is_active(self)
	var crouch_coasting := PlayerCrouchScript.is_coasting(self)
	## Walk overwrites xz; keep knock like dash so a grounded shove survives.
	SlideSurfaceScript.apply_ground_move(
		self,
		head,
		gravity,
		delta,
		_speed_boost_multiplier,
		dash_active or crouch_coasting or is_knocked(),
		dash_active,
		net_input
	)
	_apply_knockback_bleed(delta)

	NetClockScript.move_character(self)
	_separate_from_players()
	if is_fresh and is_local_owner():
		_update_interaction_prompt()


func _apply_net_look(net_input: Object) -> void:
	if head != null:
		head.rotation.y = net_input.look_yaw
	if camera_pivot != null:
		camera_pivot.rotation.x = clampf(net_input.look_pitch, deg_to_rad(-70.0), deg_to_rad(70.0))


func _apply_net_tells(net_input: Object) -> void:
	net_wand_raised = net_input.wand_raised
	if net_input.charging:
		net_charge_factor = clampf(net_input.charge_factor, 0.0, 1.0)
	else:
		net_charge_factor = 0.0
	if not is_local_owner():
		_apply_replicated_wand_tell()


func _sync_remote_tells() -> void:
	if is_local_owner():
		return
	_apply_replicated_wand_tell()


func _apply_replicated_wand_tell() -> void:
	if _wand == null:
		return
	if _wand.has_method("set_replicated_cast_tell"):
		_wand.call("set_replicated_cast_tell", net_wand_raised, net_charge_factor)
	else:
		_wand.set_raised(net_wand_raised)


func _sync_body_yaw_to_head() -> void:
	var body := get_node_or_null("Body") as Node3D
	if body == null or head == null:
		return
	body.rotation.y = head.rotation.y


func _apply_knockback_bleed(delta: float) -> void:
	PlayerCombatReactionsScript.tick_knockback_bleed(self, delta)
