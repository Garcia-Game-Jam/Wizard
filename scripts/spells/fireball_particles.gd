class_name FireballParticles
extends RefCounted

## Shared particle builders for fireball VFX (CPU trails/bursts + wand charge look).


static func make_burst(
	node_name: String,
	amount: int,
	color: Color,
	velocity_min: float,
	velocity_max: float,
	lifetime: float,
	explosiveness: float,
	gravity: Vector3 = Vector3(0.0, -4.0, 0.0),
	render_preset: String = "spark"
) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = node_name
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = explosiveness
	particles.amount = amount
	particles.lifetime = lifetime
	particles.local_coords = false
	particles.direction = Vector3.UP
	particles.spread = 180.0
	particles.initial_velocity_min = velocity_min
	particles.initial_velocity_max = velocity_max
	particles.gravity = gravity
	particles.scale_amount_min = 0.04
	particles.scale_amount_max = 0.12
	particles.color = color
	apply_render_setup(particles, render_preset)
	return particles


static func make_drift(
	node_name: String,
	amount: int,
	lifetime: float,
	color: Color,
	direction: Vector3 = Vector3.DOWN,
	spread: float = 35.0
) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = node_name
	particles.amount = amount
	particles.lifetime = lifetime
	particles.local_coords = false
	particles.direction = direction
	particles.spread = spread
	particles.initial_velocity_min = 0.4
	particles.initial_velocity_max = 1.4
	particles.gravity = Vector3(0.0, -1.2, 0.0)
	particles.scale_amount_min = 0.03
	particles.scale_amount_max = 0.08
	particles.color = color
	apply_render_setup(particles, "ember")
	return particles


static func make_smoke_trail_emitter() -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = "FireballSmokeTrail"
	particles.emitting = true
	particles.amount = 48
	particles.lifetime = 1.6
	particles.lifetime_randomness = 0.3
	particles.explosiveness = 0.0
	particles.local_coords = false
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.1
	particles.direction = Vector3(0.0, 0.2, 0.0)
	particles.spread = 38.0
	particles.initial_velocity_min = 0.25
	particles.initial_velocity_max = 0.95
	particles.gravity = Vector3(0.0, 0.35, 0.0)
	## Soft mist puffs — keep scale modest so quads never read as hard boxes.
	particles.scale_amount_min = 0.18
	particles.scale_amount_max = 0.42
	particles.color = Color(0.78, 0.72, 0.66, 0.45)
	particles.color_ramp = _make_smoke_color_ramp()
	apply_render_setup(particles, "smoke_trail")
	return particles


static func make_comet_spark_emitter() -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = "FireballCometSparks"
	particles.emitting = true
	particles.amount = 64
	particles.lifetime = 0.45
	particles.lifetime_randomness = 0.4
	particles.explosiveness = 0.0
	particles.local_coords = false
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.08
	particles.direction = Vector3.UP
	particles.spread = 32.0
	particles.initial_velocity_min = 0.9
	particles.initial_velocity_max = 2.6
	particles.gravity = Vector3(0.0, -1.8, 0.0)
	## Tiny scales — soft spark texture keeps them reading as embers, not quads.
	particles.scale_amount_min = 0.02
	particles.scale_amount_max = 0.055
	particles.color = Color(1.0, 0.82, 0.4, 1.0)
	apply_render_setup(particles, "spark")
	return particles


static func make_firework_shell(
	node_name: String,
	amount: int,
	color: Color,
	velocity_min: float,
	velocity_max: float
) -> CPUParticles3D:
	var particles := make_burst(
		node_name,
		amount,
		color,
		velocity_min,
		velocity_max,
		1.8,
		1.0,
		Vector3(0.0, -2.4, 0.0),
		"firework"
	)
	particles.lifetime_randomness = 0.2
	particles.scale_amount_min = 0.12
	particles.scale_amount_max = 0.32
	particles.color_ramp = _make_firework_color_ramp(color)
	return particles


static func make_signal_smoke_column() -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = "SignalSmokeColumn"
	particles.emitting = true
	particles.amount = 36
	particles.lifetime = 4.5
	particles.lifetime_randomness = 0.2
	particles.explosiveness = 0.0
	particles.local_coords = false
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.35
	particles.direction = Vector3.UP
	particles.spread = 8.0
	particles.initial_velocity_min = 1.2
	particles.initial_velocity_max = 2.8
	particles.gravity = Vector3(0.0, -0.15, 0.0)
	particles.scale_amount_min = 0.28
	particles.scale_amount_max = 0.65
	particles.color = Color(0.82, 0.78, 0.72, 0.4)
	particles.color_ramp = _make_smoke_color_ramp()
	apply_render_setup(particles, "smoke_trail")
	return particles


static func apply_render_setup(particles: CPUParticles3D, preset: String) -> void:
	var quad := QuadMesh.new()
	match preset:
		"smoke_trail":
			quad.size = Vector2(0.28, 0.28)
		"firework":
			quad.size = Vector2(0.18, 0.18)
		"streak":
			## Tall thin quads; pair with particle_flag_align_y for streaming trails.
			quad.size = Vector2(0.028, 0.28)
		"streak_long":
			quad.size = Vector2(0.022, 0.48)
		"ember", "spark":
			quad.size = Vector2(0.04, 0.04)
		_:
			quad.size = Vector2(0.1, 0.1)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	## Particles must never cast/receive shadows — solid quads read as black boxes.
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	match preset:
		"smoke_trail":
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
			mat.albedo_texture = make_mist_texture()
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		"ember", "spark":
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			mat.albedo_texture = make_ember_texture()
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		"streak", "streak_long":
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			mat.albedo_texture = make_ember_texture()
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			particles.particle_flag_align_y = true
		"firework":
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			mat.albedo_texture = make_ember_texture()
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_:
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			mat.albedo_texture = make_ember_texture()
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	particles.mesh = quad
	particles.material_override = mat
	particles.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))


static func make_mist_texture() -> GradientTexture2D:
	## Soft radial falloff so smoke reads as mist, not hard quads.
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.25, 0.6, 1.0])
	gradient.colors = PackedColorArray(
		[
			Color(1.0, 1.0, 1.0, 0.55),
			Color(1.0, 1.0, 1.0, 0.28),
			Color(1.0, 1.0, 1.0, 0.08),
			Color(1.0, 1.0, 1.0, 0.0),
		]
	)
	return _make_radial_texture(gradient, 128)


static func make_ember_texture() -> GradientTexture2D:
	## Tight bright core — reads as a fine spark instead of a square flake.
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.12, 0.4, 1.0])
	gradient.colors = PackedColorArray(
		[
			Color(1.0, 1.0, 1.0, 1.0),
			Color(1.0, 0.95, 0.75, 0.85),
			Color(1.0, 0.7, 0.25, 0.2),
			Color(1.0, 0.4, 0.05, 0.0),
		]
	)
	return _make_radial_texture(gradient, 64)


static func _make_radial_texture(gradient: Gradient, size: int) -> GradientTexture2D:
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = size
	tex.height = size
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	return tex


static func make_explosion_core_burst() -> CPUParticles3D:
	var particles := make_burst(
		"ExplosionCore",
		88,
		Color(1.0, 0.96, 0.82, 1.0),
		10.0,
		24.0,
		0.48,
		1.0,
		Vector3(0.0, -3.5, 0.0),
		"firework"
	)
	particles.scale_amount_min = 0.16
	particles.scale_amount_max = 0.42
	particles.color_ramp = _make_explosion_flash_ramp()
	return particles


static func make_explosion_fire_burst() -> CPUParticles3D:
	var particles := make_burst(
		"ExplosionFire",
		64,
		Color(1.0, 0.58, 0.12, 1.0),
		5.5,
		14.0,
		0.78,
		0.98,
		Vector3(0.0, -5.0, 0.0),
		"firework"
	)
	particles.scale_amount_min = 0.1
	particles.scale_amount_max = 0.28
	particles.color_ramp = _make_explosion_fire_ramp()
	return particles


static func make_explosion_smoke_burst() -> CPUParticles3D:
	var particles := make_burst(
		"ExplosionSmoke",
		36,
		Color(0.42, 0.38, 0.34, 0.55),
		1.8,
		5.5,
		1.15,
		0.82,
		Vector3(0.0, 2.8, 0.0),
		"smoke_trail"
	)
	particles.scale_amount_min = 0.22
	particles.scale_amount_max = 0.55
	particles.color_ramp = _make_smoke_color_ramp()
	return particles


static func make_explosion_ember_linger() -> CPUParticles3D:
	var particles := make_drift(
		"ExplosionEmbers",
		40,
		1.35,
		Color(1.0, 0.62, 0.18, 0.95),
		Vector3.UP,
		120.0
	)
	particles.one_shot = true
	particles.explosiveness = 0.88
	particles.initial_velocity_min = 1.4
	particles.initial_velocity_max = 4.8
	particles.gravity = Vector3(0.0, -4.5, 0.0)
	particles.scale_amount_min = 0.02
	particles.scale_amount_max = 0.06
	return particles


static func explosion_cleanup_delay_sec() -> float:
	return 1.45


static func _make_explosion_flash_ramp() -> Gradient:
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(1.0, 1.0, 0.95, 1.0))
	gradient.add_point(0.1, Color(1.0, 0.92, 0.35, 1.0))
	gradient.add_point(0.35, Color(1.0, 0.45, 0.08, 0.85))
	gradient.add_point(1.0, Color(0.45, 0.12, 0.02, 0.0))
	return gradient


static func _make_explosion_fire_ramp() -> Gradient:
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(1.0, 0.88, 0.42, 1.0))
	gradient.add_point(0.25, Color(1.0, 0.48, 0.08, 0.9))
	gradient.add_point(1.0, Color(0.35, 0.08, 0.02, 0.0))
	return gradient


static func smoke_trail_fade_delay_sec(
	particle_lifetime: float,
	padding_sec: float = 0.35
) -> float:
	return particle_lifetime + padding_sec


static func _make_smoke_color_ramp() -> Gradient:
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(0.95, 0.78, 0.48, 0.4))
	gradient.add_point(0.3, Color(0.7, 0.66, 0.62, 0.28))
	gradient.add_point(1.0, Color(0.4, 0.38, 0.36, 0.0))
	return gradient


static func _make_firework_color_ramp(base_color: Color) -> Gradient:
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(1.0, 0.98, 0.92, 1.0))
	gradient.add_point(0.15, base_color)
	gradient.add_point(0.65, base_color.lightened(0.15))
	gradient.add_point(1.0, Color(base_color.r, base_color.g, base_color.b, 0.0))
	return gradient


static func make_wand_charge_fire_texture() -> NoiseTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.22, 0.55, 0.82, 1.0])
	gradient.colors = PackedColorArray(
		[
			Color(1.0, 0.97, 0.55, 1.0),
			Color(1.0, 0.72, 0.2, 1.0),
			Color(1.0, 0.42, 0.08, 1.0),
			Color(0.95, 0.28, 0.05, 1.0),
			Color(0.75, 0.18, 0.04, 1.0),
		]
	)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.09
	noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise.fractal_lacunarity = 2.2
	noise.fractal_gain = 0.55
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = gradient
	return tex


static func make_wand_charge_core_material() -> StandardMaterial3D:
	var fire_tex := make_wand_charge_fire_texture()
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.72, 0.28, 1.0)
	mat.albedo_texture = fire_tex
	mat.uv1_scale = Vector3(2.4, 2.4, 2.4)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.12, 1.0)
	mat.emission_energy_multiplier = 1.6
	mat.emission_texture = fire_tex
	return mat


static func make_wand_charge_shell_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.35, 0.05, 0.08)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.08, 1.0)
	mat.emission_energy_multiplier = 1.0
	return mat


static func configure_wand_charge_fireball(
	bubble: MeshInstance3D, rim: MeshInstance3D, radius: float
) -> void:
	var core_mesh := SphereMesh.new()
	core_mesh.radius = radius
	core_mesh.height = radius * 2.0
	core_mesh.radial_segments = 24
	core_mesh.rings = 12
	bubble.mesh = core_mesh
	var core_mat := make_wand_charge_core_material()
	bubble.material_override = core_mat
	var shell_mesh := SphereMesh.new()
	shell_mesh.radius = radius * 1.18
	shell_mesh.height = radius * 2.36
	shell_mesh.radial_segments = 20
	shell_mesh.rings = 10
	rim.mesh = shell_mesh
	var shell_mat := make_wand_charge_shell_material()
	rim.material_override = shell_mat
	rim.visible = true


static func apply_wand_charge_fire_progress(
	core: StandardMaterial3D, shell: StandardMaterial3D, p: float
) -> void:
	var t := clampf(p, 0.0, 1.0)
	if core != null:
		core.albedo_color = Color(1.0, 0.95, 0.7, 1.0).lerp(Color(1.0, 0.72, 0.28, 1.0), t)
		core.emission = Color(1.0, 0.85, 0.4, 1.0).lerp(Color(1.0, 0.55, 0.12, 1.0), t)
		core.emission_energy_multiplier = lerpf(1.5, 4.2, t)
	if shell != null:
		shell.albedo_color = Color(1.0, 0.45, 0.08, lerpf(0.04, 0.24, t))
		shell.emission_energy_multiplier = lerpf(0.7, 2.6, t)


static func scroll_wand_charge_fire(core: StandardMaterial3D, delta: float) -> void:
	if core == null:
		return
	core.uv1_offset.x = fmod(core.uv1_offset.x + delta * 0.35, 1.0)
	core.uv1_offset.y = fmod(core.uv1_offset.y + delta * 0.55, 1.0)
