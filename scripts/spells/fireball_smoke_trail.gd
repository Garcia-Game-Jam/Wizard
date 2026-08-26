class_name FireballSmokeTrail
extends RefCounted

## World-space smoke ribbon left behind a moving fireball.

const FireballParticlesScript := preload("res://scripts/spells/fireball_particles.gd")


static func create_emitter() -> CPUParticles3D:
	return FireballParticlesScript.make_smoke_trail_emitter()


static func release_emitter(emitter: CPUParticles3D, parent: Node) -> void:
	if emitter == null or not is_instance_valid(emitter):
		return
	if emitter.get_parent() != null:
		emitter.reparent(parent)
	emitter.emitting = false
	emitter.name = "FireballSmokeTrailFade"
	var fade_delay := FireballParticlesScript.smoke_trail_fade_delay_sec(emitter.lifetime)
	var fade_timer := emitter.get_tree().create_timer(fade_delay)
	fade_timer.timeout.connect(emitter.queue_free)
