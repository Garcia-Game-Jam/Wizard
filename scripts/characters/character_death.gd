class_name CharacterDeath
extends Node

## Player/Monster Death: commit corpse/ghost after the tick loop. Clear only via revive().

const NetClockScript := preload("res://scripts/net/net_clock.gd")
const PlayerGhostScript := preload("res://scripts/characters/player_ghost.gd")

var _committed: bool = false
var _pending_knock: Vector3 = Vector3.ZERO


func _ready() -> void:
	var host := get_parent() as Character
	if host != null and not host.died.is_connected(_on_host_died):
		host.died.connect(_on_host_died)
	var nt := get_tree().root.get_node_or_null("NetworkTime") if is_inside_tree() else null
	if nt != null and nt.has_signal("after_tick_loop"):
		nt.after_tick_loop.connect(_sync_presentation)
	_sync_presentation()


func _exit_tree() -> void:
	var host := get_parent() as Character
	if host != null and host.died.is_connected(_on_host_died):
		host.died.disconnect(_on_host_died)
	var tree := get_tree()
	if tree == null:
		return
	var nt := tree.root.get_node_or_null("NetworkTime")
	if nt != null and nt.after_tick_loop.is_connected(_sync_presentation):
		nt.after_tick_loop.disconnect(_sync_presentation)


func buffer_knock(impulse: Vector3) -> void:
	_pending_knock = impulse


func clear_for_revive() -> void:
	_pending_knock = Vector3.ZERO
	if not _committed:
		return
	_committed = false
	var host := get_parent()
	if host is Player:
		PlayerGhostScript.clear(host as Player)
	elif host is Monster:
		(host as Monster).clear_dump_corpse()


func _on_host_died(_from: Variant) -> void:
	if not NetClockScript.is_ticking():
		_sync_presentation()


func _sync_presentation() -> void:
	var host := get_parent() as Character
	if host == null or not host.is_dead() or _committed:
		return
	_committed = true
	var knock := _pending_knock
	_pending_knock = Vector3.ZERO
	if host is Player:
		PlayerGhostScript.commit(host as Player, knock)
	elif host is Monster:
		(host as Monster).commit_dump_corpse(knock)
