class_name Stun
extends Effect

## Applies to Player/Stun. Same authority gate as Damage — no stun RPC.

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
	if GameState.is_multiplayer and not body.is_multiplayer_authority():
		return
	var stun := body.get_node_or_null("Stun")
	if stun == null or not stun.has_method("begin_charger_hit"):
		push_error("Stun effect needs a PlayerStun child named Stun; %s has none" % body)
		return
	var g := 18.0
	if "gravity" in body:
		g = float(body.get("gravity"))
	stun.call("begin_charger_hit", launch, g)
