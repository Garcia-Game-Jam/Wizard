@tool
class_name MonsterHearingSense
extends MonsterSense

const MonsterInterestScript := preload("res://scripts/monsters/monster_interest.gd")

## Hearing sense. Samples speaking players in range and accepts notify_heard events.

## Max distance (m) for speech / notify_heard. Cyan gizmo matches this.
@export var hear_range: float = 10.0
## How strongly heard speech pulls AI vs sight.
@export var speech_urgency: float = 1.15
## If on, speaking players in range are sampled each tick (needs voice hub).
@export var sample_speaking_players: bool = true
## Seconds a notify_heard ping stays as last-known before it expires.
@export var heard_linger_sec: float = 2.5

## Last heard world position (set by gameplay / voice bus). Cleared when stale.
var last_heard_position: Vector3 = Vector3.ZERO
var has_last_heard: bool = false
var last_heard_urgency: float = 0.0
var _heard_age_sec: float = 0.0


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not has_last_heard:
		return
	_heard_age_sec += delta
	if _heard_age_sec >= heard_linger_sec:
		clear_heard()


func append_interest_candidates(monster: CharacterBody3D, out: Array) -> void:
	if not enabled or monster == null:
		return
	if has_last_heard and last_heard_urgency > 0.0:
		_append_if_in_range(monster, last_heard_position, last_heard_urgency, out)
	if sample_speaking_players:
		_append_speaking_players(monster, out)


func _append_speaking_players(monster: CharacterBody3D, out: Array) -> void:
	var tree := monster.get_tree()
	if tree == null:
		return
	var hub := tree.root.get_node_or_null("SteamProximityVoiceHub")
	for node in tree.get_nodes_in_group("player"):
		if not (node is Node3D):
			continue
		var player := node as Node3D
		if not _player_is_speaking(hub, player, tree):
			continue
		_append_if_in_range(monster, player.global_position, speech_urgency, out)


func _player_is_speaking(hub: Node, player: Node3D, _tree: SceneTree) -> bool:
	if hub == null or not hub.has_method("is_peer_speaking"):
		return false
	var peer_id := 0
	if player.has_method("get_multiplayer_authority"):
		peer_id = int(player.get_multiplayer_authority())
	if peer_id <= 0:
		return false
	return bool(hub.call("is_peer_speaking", peer_id))


func _append_if_in_range(
	monster: CharacterBody3D, world_position: Vector3, urgency: float, out: Array
) -> void:
	var origin: Vector3 = monster.global_position
	var flat := Vector3(
		world_position.x - origin.x,
		0.0,
		world_position.z - origin.z
	)
	if flat.length() > hear_range:
		return
	out.append(
		MonsterInterestScript.from_position(world_position, urgency, &"hearing")
	)


## Gameplay hook: something loud / speech at world position.
func notify_heard(world_position: Vector3, urgency: float = -1.0) -> void:
	last_heard_position = world_position
	has_last_heard = true
	last_heard_urgency = speech_urgency if urgency < 0.0 else urgency
	_heard_age_sec = 0.0


func clear_heard() -> void:
	has_last_heard = false
	last_heard_urgency = 0.0
	_heard_age_sec = 0.0
