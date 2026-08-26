class_name TestSimpleVoiceChatPeers
extends RefCounted

const SimpleVoiceChatScript := preload("res://scripts/voice/simple_voice_chat.gd")


func run() -> int:
	var failures := 0
	failures += _test_get_peers_uses_engine_roster()
	return failures


func _test_get_peers_uses_engine_roster() -> int:
	var chat: Node = SimpleVoiceChatScript.new()
	var peers: Array = chat.call("get_peers")
	if not peers.is_empty():
		push_error("Off-tree voice must not invent remotes, got %s" % str(peers))
		chat.free()
		return 1
	chat.free()
	return 0
