class_name Stun
extends Effect

## PlayerStun child (scene node name Stun). This Resource is not that node.
## launch must be non-zero. Missing Stun child: debug warn and skip.

@export var launch: Vector3 = Vector3(0.0, 8.0, 0.0)


static func with(launch_vel: Vector3) -> Stun:
	var effect := Stun.new()
	effect.launch = launch_vel
	return effect


func apply(body: CharacterBody3D, _from: Variant) -> void:
	if launch.length_squared() < 0.0001:
		push_error("Stun.launch must be non-zero; omit Stun from the payload to skip stun")
		assert(launch.length_squared() >= 0.0001)
		return
	if not (body is Character) or not (body as Character).is_alive():
		return
	var stun := body.get_node_or_null("Stun")
	if stun == null or not stun.has_method("begin_charger_hit"):
		push_error("Stun effect needs a PlayerStun child named Stun; %s has none" % body)
		return
	var g := 18.0
	if "gravity" in body:
		g = float(body.get("gravity"))
	if not GameState.is_multiplayer or body.is_multiplayer_authority():
		stun.call("begin_charger_hit", launch, g)
		return
	var peer := int(body.get_multiplayer_authority())
	if peer > 0 and stun.has_method("rpc_begin_charger_hit"):
		stun.rpc_id(peer, "rpc_begin_charger_hit", launch)
