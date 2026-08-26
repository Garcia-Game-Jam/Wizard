class_name FireballLighting
extends RefCounted

## Shadow-casting lights for fireball VFX.

const WorldVisualLayersScript := preload("res://scripts/world_visual_layers.gd")

## Scales how strongly these lights scatter into match volumetric fog.
const VOLUMETRIC_FOG_ENERGY := 6.0


static func configure_cast_light(
	light: OmniLight3D,
	energy: float,
	light_range: float,
	color: Color,
	enable_shadows: bool = true,
	volumetric_fog_energy: float = VOLUMETRIC_FOG_ENERGY
) -> void:
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.omni_attenuation = 1.35
	light.light_specular = 0.4
	light.light_volumetric_fog_energy = volumetric_fog_energy
	light.light_cull_mask = WorldVisualLayersScript.SCENE_LIGHT_MASK
	light.shadow_caster_mask = WorldVisualLayersScript.WORLD_LIGHT_MASK
	light.shadow_enabled = enable_shadows
	if enable_shadows:
		light.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
		light.shadow_bias = 0.04
		light.shadow_normal_bias = 1.1


static func make_travel_cast_light() -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = "TravelCastLight"
	## Travel omni shadows look like moving squares on walls — keep unlit for
	## shadows; the explosion flash still casts.
	configure_cast_light(light, 1.35, 4.8, Color(1.0, 0.5, 0.14), false)
	return light


static func make_explosion_flash_light() -> OmniLight3D:
	var flash := OmniLight3D.new()
	flash.name = "ExplosionFlashLight"
	configure_cast_light(flash, 34.0, 18.0, Color(1.0, 0.9, 0.62))
	return flash


static func make_explosion_glow_light() -> OmniLight3D:
	var glow := OmniLight3D.new()
	glow.name = "ExplosionGlowLight"
	configure_cast_light(glow, 18.0, 14.0, Color(1.0, 0.42, 0.1))
	return glow

