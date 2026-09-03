@tool
class_name Wretch
extends Monster

## Rat Queen: weak eyes, moderate ears, shares rat sight, rituals when a player is known.

const HEARING_SOURCE := &"hearing"
const SUMMON_SIGHT_SOURCE := &"summon_sight"
const SUMMON_HEARING_SOURCE := &"summon_hearing"
const COMMAND_ABILITY_ID := "command_pack"
## LAST_KNOWN_SOURCE / LAST_KNOWN_URGENCY are inherited from Monster now.
const RitualPoseScript := preload("res://scripts/monsters/wretch_ritual_pose.gd")

@export var ambient_summon_cooldown_sec: float = 20.0
@export var chase_summon_cooldown_sec: float = 2.0

var _ritual: Node = null
var _last_rat_command_key: String = ""
var _last_synced_summon_ai_state: int = -1
## Snapshot used when the player slips live senses — Command Pack aims here.
var _last_known_player_pos: Vector3 = Vector3.ZERO
var _has_last_known_player: bool = false


func _ready() -> void:
	super._ready()
	_ritual = get_node_or_null("Ritual")
	## Sight/hearing + summons own aggro — do not use long proximity chase_range.
	chase_range = minf(chase_range, 3.0)
	_sync_lookdev_ritual()


func set_lookdev_pose(pose: MonsterAIScript.LookdevPose, enable_override: bool = true) -> void:
	super.set_lookdev_pose(pose, enable_override)
	_sync_lookdev_ritual()


func _sync_lookdev_ritual() -> void:
	if _ritual == null:
		_ritual = get_node_or_null("Ritual")
	if _ritual == null:
		return
	if lookdev_override and lookdev_pose == MonsterAIScript.LookdevPose.CHASE:
		if _ritual.has_method("set_ritual_phase"):
			_ritual.call("set_ritual_phase", RitualPoseScript.RitualPhase.CHASE)
		elif _ritual.has_method("set_active"):
			_ritual.call("set_active", true)
	elif _ritual.has_method("set_ritual_phase"):
		_ritual.call("set_ritual_phase", RitualPoseScript.RitualPhase.OFF)
	elif _ritual.has_method("set_active"):
		_ritual.call("set_active", false)


func is_ai_chasing() -> bool:
	return _ai_state == MonsterAIScript.State.CHASE


func get_summon_cooldown_sec() -> float:
	## Alert uses animation-gated casting in SummonRats.begin_cooldown.
	if is_ai_alert():
		return 0.0
	if is_ai_chasing() and _interest_has_player_target(_interest):
		return chase_summon_cooldown_sec
	return ambient_summon_cooldown_sec


func get_locked_player_target() -> Node3D:
	## Live player interest only (no sticky lock).
	if not _interest_has_player_target(_interest):
		return null
	return get_chase_target()


func is_locked_onto_player() -> bool:
	return get_locked_player_target() != null


func _append_default_interest_candidates(_out: Array) -> void:
	## Rat Queen uses Sight / Hearing / summon relay only — no wide proximity aggro.
	pass


func _gather_interest() -> MonsterInterest:
	if _lookdev_aggro != null and is_instance_valid(_lookdev_aggro):
		return MonsterInterestScript.from_target(_lookdev_aggro, 2.0, &"lookdev")
	var candidates: Array = []
	_append_sense_interest_candidates(candidates)
	var host := get_summon_host()
	if host != null and host.has_method("append_relayed_interests"):
		host.call("append_relayed_interests", candidates)
	_update_last_known_from_candidates(candidates)
	var preferred := _prefer_interest(candidates)
	if _interest_is_actionable(preferred) and _is_live_detection(preferred):
		return preferred
	## Lost live contact while chasing: hold last-known so we can fire Command Pack.
	if (
		_ai_state == MonsterAIScript.State.CHASE
		and _has_last_known_player
	):
		return MonsterInterestScript.from_position(
			_last_known_player_pos, LAST_KNOWN_URGENCY, LAST_KNOWN_SOURCE
		)
	if _interest_is_actionable(preferred):
		return preferred
	return preferred


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not is_alive():
		return
	if Engine.is_editor_hint() and not is_instance_valid(_lookdev_aggro):
		return
	_tick_alert_hearing()
	_direct_rats_from_interest()
	_direct_rats_alert_agitation()
	_sync_summons_to_ai_state()
	_update_ritual_pose()


func _prefer_interest(candidates: Array) -> MonsterInterest:
	## Rat vision > rat hearing > ambient host interests (including host hearing).
	var best_sight := _best_actionable_source(candidates, SUMMON_SIGHT_SOURCE)
	if best_sight != null:
		return best_sight
	var best_summon_hearing := _best_actionable_source(
		candidates, SUMMON_HEARING_SOURCE
	)
	if best_summon_hearing != null:
		return best_summon_hearing
	return super._prefer_interest(candidates)


func _best_actionable_source(candidates: Array, source: StringName) -> MonsterInterest:
	var best: MonsterInterest = null
	var best_u := 0.0
	for item in candidates:
		var interest := item as MonsterInterest
		if interest == null or interest.source != source:
			continue
		if not interest.is_actionable():
			continue
		if best == null or interest.urgency > best_u:
			best = interest
			best_u = interest.urgency
	return best


func _sync_summons_to_ai_state() -> void:
	if _ai_state == _last_synced_summon_ai_state:
		return
	_last_synced_summon_ai_state = _ai_state
	var host := get_summon_host()
	if host != null and host.has_method("sync_from_host_state"):
		host.call("sync_from_host_state", _ai_state)


func _tick_alert_hearing() -> void:
	## The ALERT band is gone with the FSM collapse — a live wretch always hunts.
	pass


func _chase_hear_range() -> float:
	var hearing := get_node_or_null("Senses/Hearing")
	if hearing != null and "hear_range" in hearing:
		return float(hearing.get("hear_range"))
	return 10.0


func _alert_hear_range() -> float:
	return _chase_hear_range() * 1.33


func _player_is_speaking(hub: Node, player: Node3D) -> bool:
	if hub == null or not hub.has_method("is_peer_speaking"):
		return false
	var peer_id := 0
	if player.has_method("get_multiplayer_authority"):
		peer_id = int(player.get_multiplayer_authority())
	if peer_id <= 0:
		return false
	return bool(hub.call("is_peer_speaking", peer_id))


func _pick_ready_ability(target: Node3D) -> Node:
	## Alert: keep casting Summon Rats until the pack is full (max 3).
	if is_ai_alert():
		var host := get_summon_host()
		if host != null and host.has_method("can_spawn") and bool(host.call("can_spawn")):
			for ability in get_combat_abilities():
				if str(ability.get("ability_id")) != "summon_rats":
					continue
				if ability.has_method("is_ready_to_cast"):
					if bool(ability.call("is_ready_to_cast", self, target)):
						return ability
				elif bool(ability.call("can_cast")):
					return ability
	## Command Pack is a lost-contact / hearing recovery shot — not while live-locked.
	if _is_live_player_detection(_interest):
		var live_pick := super._pick_ready_ability(target)
		if live_pick != null and str(live_pick.get("ability_id")) == COMMAND_ABILITY_ID:
			live_pick = null
		return live_pick
	## Lost contact: aim Command Pack at last known player position.
	if (
		is_ai_chasing()
		and _has_last_known_player
		and _interest != null
		and str(_interest.get("source")) == String(LAST_KNOWN_SOURCE)
	):
		var lost_cmd := _find_command_ability()
		if lost_cmd != null and bool(lost_cmd.call("can_cast")):
			if lost_cmd.has_method("set_pending_aim"):
				lost_cmd.call("set_pending_aim", _last_known_player_pos)
			return lost_cmd
	## Heard outside sight — fire Command Pack at the sound immediately.
	var hearing_aim = get_hearing_command_aim()
	if hearing_aim is Vector3:
		for ability in get_combat_abilities():
			if str(ability.get("ability_id")) != COMMAND_ABILITY_ID:
				continue
			if not bool(ability.call("can_cast")):
				continue
			if ability.has_method("set_pending_aim"):
				ability.call("set_pending_aim", hearing_aim as Vector3)
			return ability
	return super._pick_ready_ability(target)


func _try_start_cast(target: Node3D) -> bool:
	## Lost-contact Command Pack (no live player Node3D).
	if (
		is_ai_chasing()
		and not _is_live_player_detection(_interest)
		and _has_last_known_player
	):
		var lost_cmd := _find_command_ability()
		if lost_cmd != null and bool(lost_cmd.call("can_cast")):
			if lost_cmd.has_method("set_pending_aim"):
				lost_cmd.call("set_pending_aim", _last_known_player_pos)
			_begin_ability_windup(lost_cmd)
			_tick_cast_windup(0.0, null)
			return true
	## Hearing casts have no player Node3D — still start Command Pack via pending aim.
	var hearing_aim = get_hearing_command_aim()
	if (
		(target == null or not is_instance_valid(target))
		and hearing_aim is Vector3
	):
		var cmd := _find_command_ability()
		if cmd != null and bool(cmd.call("can_cast")):
			if cmd.has_method("set_pending_aim"):
				cmd.call("set_pending_aim", hearing_aim as Vector3)
			_begin_ability_windup(cmd)
			## Faster reaction to sound than a full visual ritual charge.
			_cast_windup_left = minf(_cast_windup_left, 0.35)
			_tick_cast_windup(0.0, null)
			return true
	return super._try_start_cast(target)


func _tick_cast_windup(delta: float, target: Node3D) -> void:
	## Face last-known / heard point while winding up a recovery Command Pack.
	if target == null and _casting_ability != null:
		var aim_point = _command_aim_point()
		if aim_point is Vector3:
			var aim: Vector3 = aim_point as Vector3
			var toward := Vector3(
				aim.x - global_position.x,
				0.0,
				aim.z - global_position.z
			)
			_face_toward_hearing(toward, delta)
	## Allow Command Pack to finish without a player Node3D (uses pending aim).
	if (
		_casting_ability != null
		and str(_casting_ability.get("ability_id")) == COMMAND_ABILITY_ID
		and (target == null or not is_instance_valid(target))
	):
		velocity.x = 0.0
		velocity.z = 0.0
		_cast_windup_left -= delta
		if _cast_windup_left > 0.0:
			return
		var ability := _casting_ability
		_casting_ability = null
		_cast_windup_left = 0.0
		if ability != null and is_instance_valid(ability) and ability.has_method("begin_cast"):
			ability.call("begin_cast", self, null)
			_on_ability_cast_fired(ability)
		return
	super._tick_cast_windup(delta, target)


func _command_aim_point():
	if _has_last_known_player:
		return _last_known_player_pos
	return get_hearing_command_aim()


func get_hearing_command_aim():
	## Sound aim only when not live-tracking a player and sound is outside sight.
	if _is_live_player_detection(_interest):
		return null
	if _interest == null:
		return null
	if str(_interest.get("source")) != String(HEARING_SOURCE):
		return null
	if not bool(_interest.get("has_goal_position")):
		return null
	var goal: Vector3 = _interest.call("resolved_goal_position", global_position)
	var sight_r := _visual_sight_range()
	var flat := Vector3(
		goal.x - global_position.x,
		0.0,
		goal.z - global_position.z
	)
	if flat.length() <= sight_r:
		return null
	return goal


func _visual_sight_range() -> float:
	var sight := get_node_or_null("Senses/Sight")
	if sight != null and "sight_range" in sight:
		return float(sight.get("sight_range"))
	return 2.5


func _find_command_ability() -> Node:
	for ability in get_combat_abilities():
		if str(ability.get("ability_id")) == COMMAND_ABILITY_ID:
			return ability
	return null


func _tick_chase(delta: float) -> void:
	## Packmaster stands still while directing rats / ritualizing, except for
	## short post-Command-Pack reposition hops from the shared chase move API.
	if not _interest_is_actionable(_interest):
		_cancel_cast()
		_clear_chase_move()
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var target: Node3D = null
	if _is_live_player_detection(_interest):
		target = get_chase_target()

	if _try_tick_chase_reposition(delta, target):
		return

	velocity.x = 0.0
	velocity.z = 0.0
	if target:
		var toward := Vector3(
			target.global_position.x - global_position.x,
			0.0,
			target.global_position.z - global_position.z
		)
		_face_horizontal(toward)
		return
	## Last-known / hearing: face the memory point slowly, stay put (orb windup).
	if _interest != null and _interest.get("has_goal_position"):
		var goal := get_chase_goal(global_position)
		var toward_sound := Vector3(
			goal.x - global_position.x,
			0.0,
			goal.z - global_position.z
		)
		_face_toward_hearing(toward_sound, delta)


func _uses_continuous_chase_move_timer() -> bool:
	return false


func _on_ability_cast_fired(ability: Node) -> void:
	if ability == null or not is_instance_valid(ability):
		return
	if str(ability.get("ability_id")) != COMMAND_ABILITY_ID:
		return
	if _lookdev_aggro != null and is_instance_valid(_lookdev_aggro):
		return
	_reassess_aggro_after_command_pack()


func _reassess_aggro_after_command_pack() -> void:
	## Orb is the lost-contact recovery shot.
	_interest = null
	_clear_chase_move()
	if _has_last_known_player:
		var host := get_summon_host()
		if host != null and host.has_method("sync_alert_sound"):
			host.call("sync_alert_sound", _last_known_player_pos)


func _tick_alert(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	var hear_goal = _hearing_face_goal()
	if hear_goal is Vector3:
		var goal: Vector3 = hear_goal as Vector3
		var toward := Vector3(
			goal.x - global_position.x,
			0.0,
			goal.z - global_position.z
		)
		_face_toward_hearing(toward, delta)


func _hearing_face_goal():
	## Prefer live hearing interest, then lingering last-heard point.
	if (
		_interest != null
		and str(_interest.get("source")) == String(HEARING_SOURCE)
		and bool(_interest.get("has_goal_position"))
	):
		return _interest.call("resolved_goal_position", global_position)
	var hearing := get_node_or_null("Senses/Hearing")
	if hearing != null and bool(hearing.get("has_last_heard")):
		return hearing.get("last_heard_position")
	return null


func _face_toward_hearing(desired: Vector3, delta: float) -> void:
	## Half the normal face turn rate when reacting to sound.
	_face_horizontal_at_speed(desired, delta, face_turn_speed_rad * 0.5)


func _direct_rats_from_interest() -> void:
	## Hearing no longer auto-sends rats — Command Pack orb handles investigate on arrival.
	if _ai_state != MonsterAIScript.State.CHASE:
		_last_rat_command_key = ""


func _direct_rats_alert_agitation() -> void:
	## While alert, push the heard point so rats scurry toward it more often.
	var host := get_summon_host()
	if host == null:
		return
	if not is_ai_alert():
		if host.has_method("clear_alert_sound"):
			host.call("clear_alert_sound")
		return
	var sound = _resolve_alert_sound_position()
	if sound is Vector3 and host.has_method("sync_alert_sound"):
		host.call("sync_alert_sound", sound as Vector3)


func _resolve_alert_sound_position():
	var face = _hearing_face_goal()
	if face is Vector3:
		return face
	var hearing := get_node_or_null("Senses/Hearing")
	if hearing != null and bool(hearing.get("has_last_heard")):
		return hearing.get("last_heard_position")
	if _has_last_known_player:
		return _last_known_player_pos
	var alert_r := _alert_hear_range()
	var tree := get_tree()
	if tree == null:
		return null
	var hub := tree.root.get_node_or_null("SteamProximityVoiceHub")
	var best: Variant = null
	var best_dist := INF
	for node in tree.get_nodes_in_group("player"):
		if not (node is Node3D):
			continue
		var player := node as Node3D
		if not _player_is_speaking(hub, player):
			continue
		var flat := Vector3(
			player.global_position.x - global_position.x,
			0.0,
			player.global_position.z - global_position.z
		)
		var dist := flat.length()
		if dist > alert_r or dist >= best_dist:
			continue
		best_dist = dist
		best = player.global_position
	return best


func _update_ritual_pose() -> void:
	if _ritual == null:
		_ritual = get_node_or_null("Ritual")
	if _ritual == null:
		return
	var phase: int = RitualPoseScript.RitualPhase.OFF
	if (
		_casting_ability != null
		or (
			is_ai_chasing()
			and (
				_is_live_player_detection(_interest)
				or (
					_interest != null
					and str(_interest.get("source")) == String(LAST_KNOWN_SOURCE)
				)
				or get_hearing_command_aim() is Vector3
			)
		)
	):
		phase = RitualPoseScript.RitualPhase.CHASE
	elif is_ai_alert():
		phase = RitualPoseScript.RitualPhase.ALERT
	if _ritual.has_method("set_ritual_phase"):
		_ritual.call("set_ritual_phase", phase)
	elif _ritual.has_method("set_active"):
		_ritual.call("set_active", phase != RitualPoseScript.RitualPhase.OFF)


func _update_last_known_from_candidates(candidates: Array) -> void:
	for item in candidates:
		var interest := item as MonsterInterest
		if interest == null:
			continue
		var target := interest.get_live_target()
		if target and target.is_in_group("player"):
			_last_known_player_pos = target.global_position
			_has_last_known_player = true
			return
		## Hearing / investigate positions also refresh last known while chasing.
		if (
			is_ai_chasing()
			and interest.has_goal_position
			and interest.source == HEARING_SOURCE
		):
			_last_known_player_pos = interest.resolved_goal_position(global_position)
			_has_last_known_player = true


func _is_live_detection(interest: MonsterInterest) -> bool:
	return _is_live_player_detection(interest)


func _is_live_player_detection(interest: MonsterInterest) -> bool:
	## Own sight, lookdev dummy, or rat sight of a player — not sticky memory.
	if not _interest_has_player_target(interest):
		return false
	return (
		interest.source == &"sight"
		or interest.source == &"lookdev"
		or interest.source == SUMMON_SIGHT_SOURCE
	)


func _interest_has_player_target(interest: MonsterInterest) -> bool:
	if interest == null:
		return false
	var target := interest.get_live_target()
	return target != null and target.is_in_group("player")
