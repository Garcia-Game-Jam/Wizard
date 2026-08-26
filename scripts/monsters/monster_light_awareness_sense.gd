@tool
class_name MonsterLightAwarenessSense
extends MonsterSense

const MonsterInterestScript := preload("res://scripts/monsters/monster_interest.gd")

## Stub light awareness. Samples can be wired to OmniLights / flare later.

## Max distance (m) to a notify_light point. Yellow gizmo matches this.
@export var sense_range: float = 10.0
## How strongly a bright point pulls (or pushes, if flee_bright).
@export var light_urgency: float = 1.1
## If on, bright interest is treated as something to avoid (v1 hint only).
@export var flee_bright: bool = true

## Last sampled bright point (set by notify_light or future probe).
var last_light_position: Vector3 = Vector3.ZERO
var has_last_light: bool = false
var last_light_level: float = 0.0


func append_interest_candidates(_monster: CharacterBody3D, out: Array) -> void:
	if not enabled or not has_last_light or last_light_level <= 0.0:
		return
	if _monster == null:
		return
	var origin: Vector3 = _monster.global_position
	var flat := Vector3(
		last_light_position.x - origin.x,
		0.0,
		last_light_position.z - origin.z
	)
	if flat.length() > sense_range:
		return
	var interest = MonsterInterestScript.from_position(
		last_light_position,
		light_urgency * last_light_level,
		&"light"
	)
	interest.avoid_light = flee_bright
	interest.prefer_dark = flee_bright
	out.append(interest)


func notify_light(world_position: Vector3, level: float = 1.0) -> void:
	last_light_position = world_position
	has_last_light = true
	last_light_level = maxf(0.0, level)


func clear_light() -> void:
	has_last_light = false
	last_light_level = 0.0
