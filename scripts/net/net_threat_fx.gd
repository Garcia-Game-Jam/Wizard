class_name NetThreatFx
extends RefCounted

## Host-authored ember VFX. PredictiveSynchronizer is local-only, so guests
## instantiate the same scenes from an arena RPC. Hits stay host-gated.

const EmberLobProjectileScript := preload(
	"res://scripts/monsters/abilities/ember_lob_projectile.gd"
)
const EmberHaloProjectileScript := preload(
	"res://scripts/monsters/abilities/ember_halo_projectile.gd"
)
const EmberDashTrailSegmentScript := preload(
	"res://scripts/monsters/abilities/ember_dash_trail_segment.gd"
)
const GameWorldScript := preload("res://scripts/game_world.gd")

const KIND_LOB := "ember_lob"
const KIND_HALO := "ember_halo"
const KIND_DASH := "ember_dash"

static var _applying := false


static func broadcast(kind: String, origin: Vector3, extra: Dictionary) -> void:
	if _applying:
		return
	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return
	var arena: Node = GameWorldScript.find_match_root(tree as SceneTree)
	if arena != null and arena.has_method("broadcast_threat_fx"):
		arena.call("broadcast_threat_fx", kind, origin, extra)


static func apply(kind: String, origin: Vector3, extra: Dictionary) -> void:
	_applying = true
	var parent := _fx_parent()
	match kind:
		KIND_LOB:
			EmberLobProjectileScript.spawn(
				parent, origin, null, null, true, _vec(extra, "aim")
			)
		KIND_HALO:
			EmberHaloProjectileScript.spawn(
				parent, origin, _vec(extra, "toward"), null, true
			)
		KIND_DASH:
			EmberDashTrailSegmentScript.spawn(
				parent,
				origin,
				_vec(extra, "dir"),
				float(extra.get("width", 0.5)),
				float(extra.get("length", 0.35)),
				float(extra.get("lifetime", 4.0)),
				0.0,
				1.0,
				0.5,
				null,
				true
			)
	_applying = false


static func pack_vec(key: String, value: Vector3) -> Dictionary:
	return {
		"%s_x" % key: value.x,
		"%s_y" % key: value.y,
		"%s_z" % key: value.z,
	}


static func _vec(extra: Dictionary, key: String) -> Vector3:
	return Vector3(
		float(extra.get("%s_x" % key, 0.0)),
		float(extra.get("%s_y" % key, 0.0)),
		float(extra.get("%s_z" % key, 0.0))
	)


static func _fx_parent() -> Node:
	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return null
	var arena: Node = GameWorldScript.find_match_root(tree as SceneTree)
	if arena == null:
		return (tree as SceneTree).current_scene
	var monsters := arena.get_node_or_null("Monsters")
	return monsters if monsters != null else arena
