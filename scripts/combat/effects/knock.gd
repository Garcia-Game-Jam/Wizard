class_name Knock
extends Effect

## Shove plus bleed. impulse must be non-zero — omit this resource for no knock.
## from_impact: rebuilds impulse per body from the impact point.
## Authored impulse then holds (horizontal, up, unused) magnitudes.

@export var impulse: Vector3 = Vector3(9.0, 3.5, 0.0)
@export var from_impact: bool = false


static func with(world_impulse: Vector3) -> Knock:
	var effect := Knock.new()
	effect.impulse = world_impulse
	effect.from_impact = false
	return effect


static func impulse_from_dir(
	dir: Vector3, horizontal: float = 9.0, up: float = 3.5
) -> Vector3:
	var knock_dir := dir
	if knock_dir.length_squared() < 0.0001:
		knock_dir = Vector3.FORWARD
	else:
		knock_dir = knock_dir.normalized()
	var flat := Vector3(knock_dir.x, 0.0, knock_dir.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	else:
		flat = flat.normalized()
	return flat * horizontal + Vector3.UP * up


func apply(body: CharacterBody3D, _from: Variant) -> void:
	if impulse.length_squared() < 0.0001:
		push_error("Knock.impulse must be non-zero; omit Knock from the payload to skip shove")
		assert(impulse.length_squared() >= 0.0001)
		return
	if body is Character:
		(body as Character).apply_knockback(impulse, impulse)
