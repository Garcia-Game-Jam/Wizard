class_name CharacterDeath
extends Node

## Player/Monster Death: commit corpse/ghost after the tick loop.
## Corpse props live under Arena/Corpses until stage despawn. Revive only un-ghosts.

const NetClockScript := preload("res://scripts/net/net_clock.gd")
const PlayerGhostScript := preload("res://scripts/characters/player_ghost.gd")

var _committed: bool = false
var _pending_knock: Vector3 = Vector3.ZERO


func _ready() -> void:
	var host := get_parent() as Character
	if host != null:
		if not host.died.is_connected(_on_host_died):
			host.died.connect(_on_host_died)
		if not host.revived.is_connected(_on_host_revived):
			host.revived.connect(_on_host_revived)
	var nt := get_tree().root.get_node_or_null("NetworkTime") if is_inside_tree() else null
	if nt != null and nt.has_signal("after_tick_loop"):
		nt.after_tick_loop.connect(_sync_presentation)
	_sync_presentation()


func _exit_tree() -> void:
	var host := get_parent() as Character
	if host != null:
		if host.died.is_connected(_on_host_died):
			host.died.disconnect(_on_host_died)
		if host.revived.is_connected(_on_host_revived):
			host.revived.disconnect(_on_host_revived)
	var tree := get_tree()
	if tree == null:
		return
	var nt := tree.root.get_node_or_null("NetworkTime")
	if nt != null and nt.after_tick_loop.is_connected(_sync_presentation):
		nt.after_tick_loop.disconnect(_sync_presentation)


func buffer_knock(impulse: Vector3) -> void:
	_pending_knock = impulse


func _on_host_died(_from: Variant) -> void:
	if not NetClockScript.is_ticking():
		_sync_presentation()


func _on_host_revived() -> void:
	if not NetClockScript.is_ticking():
		_sync_presentation()


func _sync_presentation() -> void:
	var host := get_parent() as Character
	if host == null:
		return
	## Pad rez: suppress death commit until sim stands up; then un-ghost only.
	if host is Player and (host as Player)._pad_rez_pending:
		var player := host as Player
		if not player.is_alive():
			return
		player._pad_rez_pending = false
		_release_pawn_presentation(host)
		return
	if host.is_dead():
		if _committed:
			return
		_committed = true
		var knock := _pending_knock
		_pending_knock = Vector3.ZERO
		if host is Player:
			PlayerGhostScript.commit(host as Player, knock)
		elif host is Monster:
			(host as Monster).commit_corpse(knock)
		return
	if _committed:
		_release_pawn_presentation(host)


func _release_pawn_presentation(host: Character) -> void:
	_pending_knock = Vector3.ZERO
	_committed = false
	if host is Player:
		PlayerGhostScript.end_ghost(host as Player)
	elif host is Monster:
		(host as Monster).release_corpse_presentation()
