class_name UiScale
extends RefCounted

## Scales menu/HUD layout from a 1920x1080 design reference.

const DESIGN_REFERENCE := Vector2(1920.0, 1080.0)
const MIN_SCALE := 0.55
const MAX_SCALE := 2.5


static func scale_factor(viewport_size: Vector2) -> float:
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return 1.0
	var factor := minf(
		viewport_size.x / DESIGN_REFERENCE.x,
		viewport_size.y / DESIGN_REFERENCE.y
	)
	return clampf(factor, MIN_SCALE, MAX_SCALE)


static func scaled(value: float, viewport_size: Vector2, minimum: float = 1.0) -> int:
	return maxi(int(round(value * scale_factor(viewport_size))), int(round(minimum)))
