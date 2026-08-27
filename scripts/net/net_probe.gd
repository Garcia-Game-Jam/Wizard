class_name NetProbe
extends RefCounted

## Backend-neutral read model for diagnostics. NetDiag talks only to this, never
## to a specific netcode library, so swapping netfox for another backend later is
## one new subclass + one line in create(), not a NetDiag rewrite.
##
## A backend that lacks a concept (rollback depth, clock stretch) returns a
## neutral value (0 / 1.0). CSV columns stay stable across backends so captures
## and tools/analyze_netdiag.py keep comparing like for like.

## Runtime load (not preload) so the netfox subclass, which extends this class,
## does not form a parse-time cycle.
const NETFOX_PROBE_PATH := "res://scripts/net/net_probe_netfox.gd"

var _tree: SceneTree = null


static func create(tree: SceneTree) -> NetProbe:
	var probe: NetProbe = null
	if tree != null and tree.root.get_node_or_null("NetworkTime") != null:
		var netfox_script := load(NETFOX_PROBE_PATH) as GDScript
		if netfox_script != null:
			probe = netfox_script.new()
	if probe == null:
		probe = NetProbe.new()
	probe._tree = tree
	probe._setup()
	return probe


## Subclasses hook backend signals here (constructor has no _tree yet).
func _setup() -> void:
	pass


func backend_id() -> String:
	return "none"


## True once the netcode clock/session is live and ticking.
func is_running() -> bool:
	return false


func current_tick() -> int:
	return 0


## Ticks resimulated in the last rollback pass. 0 for backends without rollback.
func rollback_depth() -> int:
	return 0


## {stretch: float, offset: float, rtt: float}. Neutral defaults when N/A.
func clock_health() -> Dictionary:
	return {"stretch": 1.0, "offset": 0.0, "rtt": 0.0}


## {us: int, ticks: int} for the tick loop since the last call, or {} if no loop
## ran / the backend has no discrete tick loop. NetDiag calls this once per frame.
func pop_tick_loop() -> Dictionary:
	return {}


## Whatever backend settings matter for comparing captures. Goes into meta.json.
func config_snapshot() -> Dictionary:
	return {}


func peer_count() -> int:
	if _tree == null:
		return 0
	var mp := _tree.get_multiplayer()
	if mp == null or not mp.has_multiplayer_peer():
		return 0
	return mp.get_peers().size() + 1


func autoload(node_name: String) -> Node:
	if _tree == null:
		return null
	return _tree.root.get_node_or_null(node_name)
