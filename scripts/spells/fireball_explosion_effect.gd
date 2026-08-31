class_name FireballExplosionEffect
extends Node3D

## Impact burst when a fireball hits geometry.

const FireballParticlesScript := preload("res://scripts/spells/fireball_particles.gd")
const FireballLightingScript := preload("res://scripts/spells/fireball_lighting.gd")

var _played := false


func _ready() -> void:
	if not _played:
		_play(clampf(scale.x, 0.08, 1.0))


static func spawn(
	parent: Node,
	world_position: Vector3,
	fx_scale: float = 1.0
) -> FireballExplosionEffect:
	var effect := FireballExplosionEffect.new()
	effect.scale = Vector3.ONE * clampf(fx_scale, 0.08, 1.0)
	parent.add_child(effect)
	effect.global_position = world_position
	return effect


func _play(fx_scale: float = 1.0) -> void:
	if _played:
		return
	_played = true
	scale = Vector3.ONE * fx_scale
	var flash := FireballLightingScript.make_explosion_flash_light()
	flash.light_energy *= fx_scale
	flash.omni_range *= fx_scale
	add_child(flash)

	var glow := FireballLightingScript.make_explosion_glow_light()
	glow.light_energy *= fx_scale
	glow.omni_range *= fx_scale
	add_child(glow)

	_emit_particles(FireballParticlesScript.make_explosion_core_burst())
	_emit_particles(FireballParticlesScript.make_explosion_fire_burst())
	_emit_particles(FireballParticlesScript.make_explosion_smoke_burst())
	_emit_particles(FireballParticlesScript.make_explosion_ember_linger())

	var flash_range := flash.omni_range * (26.0 / 18.0)
	var flash_tween := create_tween()
	flash_tween.set_parallel(true)
	flash_tween.tween_property(flash, "light_energy", 0.0, 0.14)\
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	flash_tween.tween_property(flash, "omni_range", flash_range, 0.06)\
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	flash_tween.tween_property(glow, "light_energy", 0.0, 0.9)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	var cleanup := create_tween()
	cleanup.tween_interval(FireballParticlesScript.explosion_cleanup_delay_sec())
	cleanup.tween_callback(queue_free)


func _emit_particles(particles: CPUParticles3D) -> void:
	add_child(particles)
	particles.emitting = true
	particles.restart()
