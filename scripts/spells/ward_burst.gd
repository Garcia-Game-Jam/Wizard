class_name WardBurst
extends Node3D

## One-shot GPU shatter: thin glass shards from the dome, then gravity.

const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")

const SHARD_COUNT := 64
const LIFE_SEC := 0.85


func setup(burst_radius: float, rim: Color) -> void:
	top_level = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	var radius := maxf(burst_radius, 0.2)
	var shards := _make_shards(radius, rim)
	add_child(shards)
	var life := Timer.new()
	life.one_shot = true
	life.wait_time = LIFE_SEC + 0.2
	life.timeout.connect(queue_free)
	add_child(life)
	life.start()
	shards.restart()
	shards.emitting = true


func _make_shards(radius: float, rim: Color) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "Shards"
	particles.amount = SHARD_COUNT
	particles.lifetime = LIFE_SEC
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.randomness = 0.55
	particles.local_coords = false
	particles.emitting = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.layers = WorldVisualLayersScript.WORLD
	particles.position = Vector3(0.0, 0.0, -radius * 0.5)
	particles.visibility_aabb = AABB(
		Vector3(-radius * 4.0, -radius * 6.0, -radius * 4.0),
		Vector3(radius * 8.0, radius * 10.0, radius * 8.0)
	)
	particles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	particles.process_material = _make_process(radius, rim)
	particles.draw_pass_1 = _make_shard_mesh(rim)
	return particles


func _make_process(radius: float, rim: Color) -> ParticleProcessMaterial:
	var pmat := ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	pmat.emission_sphere_radius = radius * 0.62
	pmat.direction = Vector3(0.0, 0.15, -0.2)
	pmat.spread = 48.0
	pmat.initial_velocity_min = 0.35
	pmat.initial_velocity_max = 1.1
	pmat.radial_velocity_min = 1.8
	pmat.radial_velocity_max = 3.6
	pmat.gravity = Vector3(0.0, -9.2, 0.0)
	pmat.damping_min = 0.2
	pmat.damping_max = 0.8
	pmat.angle_min = -180.0
	pmat.angle_max = 180.0
	pmat.angular_velocity_min = 120.0
	pmat.angular_velocity_max = 420.0
	pmat.scale_min = 0.45
	pmat.scale_max = 1.35
	pmat.color = Color(rim.r, rim.g, rim.b, 0.9)
	pmat.color_ramp = _make_fade_ramp(rim)
	pmat.scale_curve = _make_scale_curve()
	return pmat


func _make_fade_ramp(rim: Color) -> GradientTexture1D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	grad.colors = PackedColorArray(
		[
			Color(rim.r, rim.g, rim.b, 0.92),
			Color(rim.r, rim.g, rim.b, 0.7),
			Color(rim.r, rim.g, rim.b, 0.0),
		]
	)
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	return ramp


func _make_scale_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.28))
	var tex := CurveTexture.new()
	tex.curve = curve
	return tex


func _make_shard_mesh(rim: Color) -> Mesh:
	var mesh := PrismMesh.new()
	mesh.size = Vector3(0.13, 0.007, 0.09)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.metallic = 0.28
	mat.roughness = 0.07
	mat.albedo_color = Color(0.78, 0.9, 1.0, 0.72)
	mat.emission_enabled = true
	mat.emission = Color(rim.r, rim.g, rim.b)
	mat.emission_energy_multiplier = 0.55
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mesh.material = mat
	return mesh
