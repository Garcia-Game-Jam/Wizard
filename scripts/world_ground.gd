class_name WorldGround
extends RefCounted

## Sample floor height under an XZ point (maze static geometry).

const WORLD_COLLISION_MASK := 1
const RAY_TOP := 24.0
const RAY_BOTTOM := -8.0


static func sample_ground_y(
	world_3d: World3D,
	at: Vector3,
	fallback_y: float = 0.0
) -> float:
	if world_3d == null:
		return fallback_y
	var space := world_3d.direct_space_state
	if space == null:
		return fallback_y
	var from := Vector3(at.x, RAY_TOP, at.z)
	var to := Vector3(at.x, RAY_BOTTOM, at.z)
	var ray := PhysicsRayQueryParameters3D.create(from, to)
	ray.collision_mask = WORLD_COLLISION_MASK
	ray.hit_from_inside = true
	var hit := space.intersect_ray(ray)
	if hit.is_empty():
		return fallback_y
	return float(hit.position.y)


static func with_height_above_ground(
	world_3d: World3D,
	pos: Vector3,
	height_above: float,
	fallback_ground_y: float = 0.0
) -> Vector3:
	var ground_y := sample_ground_y(world_3d, pos, fallback_ground_y)
	return Vector3(pos.x, ground_y + height_above, pos.z)
