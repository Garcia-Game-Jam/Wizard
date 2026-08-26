class_name FlareParticles
extends RefCounted

## GPU-only flare VFX builders. Tunables are authored on FlareEffect and applied here.

const FireballParticlesScript := preload("res://scripts/spells/fireball_particles.gd")

const DEFAULT_AMOUNT := 24
const DEFAULT_LIFETIME := 0.38
const DEFAULT_VELOCITY_MIN := 0.6
const DEFAULT_VELOCITY_MAX := 2.2
const DEFAULT_SCALE_MIN := 0.018
const DEFAULT_SCALE_MAX := 0.05
const DEFAULT_STREAK_WIDTH := 0.035
const DEFAULT_STREAK_LENGTH := 0.22
const DEFAULT_COLOR := Color(1.0, 0.58, 0.12, 0.95)


static func make_comet_sparks(settings: Dictionary = {}) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "CometSparks"
	particles.amount = maxi(int(settings.get("amount", DEFAULT_AMOUNT)), 1)
	particles.lifetime = maxf(float(settings.get("lifetime", DEFAULT_LIFETIME)), 0.05)
	particles.randomness = clampf(float(settings.get("randomness", 0.35)), 0.0, 1.0)
	particles.explosiveness = 0.0
	particles.local_coords = false
	particles.fixed_fps = 60
	particles.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var pmat := ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pmat.emission_sphere_radius = maxf(float(settings.get("emission_radius", 0.045)), 0.005)
	pmat.direction = Vector3(0.0, 1.0, 0.0)
	pmat.spread = clampf(float(settings.get("spread", 28.0)), 0.0, 180.0)
	pmat.initial_velocity_min = float(settings.get("velocity_min", DEFAULT_VELOCITY_MIN))
	pmat.initial_velocity_max = float(settings.get("velocity_max", DEFAULT_VELOCITY_MAX))
	pmat.gravity = Vector3(0.0, float(settings.get("gravity", -0.9)), 0.0)
	pmat.scale_min = float(settings.get("scale_min", DEFAULT_SCALE_MIN))
	pmat.scale_max = float(settings.get("scale_max", DEFAULT_SCALE_MAX))
	pmat.color = settings.get("color", DEFAULT_COLOR) as Color
	pmat.particle_flag_align_y = true
	particles.process_material = pmat

	var quad := QuadMesh.new()
	quad.size = Vector2(
		float(settings.get("streak_width", DEFAULT_STREAK_WIDTH)),
		float(settings.get("streak_length", DEFAULT_STREAK_LENGTH))
	)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = FireballParticlesScript.make_ember_texture()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	quad.material = mat
	particles.draw_pass_1 = quad
	return particles


static func apply_comet_sparks(particles: GPUParticles3D, settings: Dictionary) -> void:
	if particles == null:
		return
	particles.amount = maxi(int(settings.get("amount", DEFAULT_AMOUNT)), 1)
	particles.lifetime = maxf(float(settings.get("lifetime", DEFAULT_LIFETIME)), 0.05)
	particles.randomness = clampf(float(settings.get("randomness", 0.35)), 0.0, 1.0)
	var pmat := particles.process_material as ParticleProcessMaterial
	if pmat == null:
		return
	pmat.emission_sphere_radius = maxf(float(settings.get("emission_radius", 0.045)), 0.005)
	pmat.spread = clampf(float(settings.get("spread", 28.0)), 0.0, 180.0)
	pmat.initial_velocity_min = float(settings.get("velocity_min", DEFAULT_VELOCITY_MIN))
	pmat.initial_velocity_max = float(settings.get("velocity_max", DEFAULT_VELOCITY_MAX))
	pmat.gravity = Vector3(0.0, float(settings.get("gravity", -0.9)), 0.0)
	pmat.scale_min = float(settings.get("scale_min", DEFAULT_SCALE_MIN))
	pmat.scale_max = float(settings.get("scale_max", DEFAULT_SCALE_MAX))
	pmat.color = settings.get("color", DEFAULT_COLOR) as Color
	var quad := particles.draw_pass_1 as QuadMesh
	if quad != null:
		quad.size = Vector2(
			float(settings.get("streak_width", DEFAULT_STREAK_WIDTH)),
			float(settings.get("streak_length", DEFAULT_STREAK_LENGTH))
		)
