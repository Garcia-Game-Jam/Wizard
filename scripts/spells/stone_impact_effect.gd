class_name StoneImpactEffect
extends Node3D

## Small dust + chip burst when a thrown stone lands or hits.

const FireballParticlesScript := preload("res://scripts/spells/fireball_particles.gd")
const CLEANUP_DELAY_SEC := 0.9

var _played := false


func _ready() -> void:
	if not _played:
		_play()


static func spawn(parent: Node, world_position: Vector3) -> StoneImpactEffect:
	if parent == null:
		return null
	var effect := StoneImpactEffect.new()
	parent.add_child(effect)
	effect.global_position = world_position
	return effect


func _play() -> void:
	if _played:
		return
	_played = true
	_emit(
		FireballParticlesScript.make_burst(
			"Dust",
			20,
			Color(0.55, 0.5, 0.45, 0.5),
			1.0,
			2.8,
			0.55,
			0.9,
			Vector3(0.0, 0.4, 0.0),
			"smoke_trail"
		)
	)
	_emit(
		FireballParticlesScript.make_burst(
			"Chips",
			12,
			Color(0.4, 0.38, 0.35, 1.0),
			2.5,
			6.0,
			0.4,
			1.0,
			Vector3(0.0, -9.0, 0.0),
			"spark"
		)
	)
	var cleanup := create_tween()
	cleanup.tween_interval(CLEANUP_DELAY_SEC)
	cleanup.tween_callback(queue_free)


func _emit(particles: CPUParticles3D) -> void:
	add_child(particles)
	particles.emitting = true
	particles.restart()
