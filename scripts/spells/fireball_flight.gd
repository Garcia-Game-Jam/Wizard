class_name FireballFlight
extends RefCounted

## Pure fireball trajectory rules — unit-testable without a scene tree.

const MAX_LIFETIME := 2.5
const VISUAL_RADIUS := 0.22
const HIT_RADIUS := 0.16


static func should_finish_normal(elapsed_sec: float) -> bool:
	return elapsed_sec >= MAX_LIFETIME
