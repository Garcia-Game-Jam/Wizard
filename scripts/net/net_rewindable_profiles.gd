class_name NetRewindableProfiles
extends RefCounted

## Interpolators and non-character bodies. Living characters author state via
## net_state_paths(); playable input via PlayerNetInput.NET_FIELDS.

const PlayerNetInputScript := preload("res://scripts/net/player_net_input.gd")

const PLAYABLE := "playable"
const WORLD_PROP := "world_prop"
const PROJECTILE := "projectile"
const VOLUME := "volume"
const CHARGE := "charge"
const COVER := "cover"
const CORPSE := "corpse"


static func state_paths(profile: String) -> Array[String]:
	var paths: Array[String] = []
	match profile:
		PLAYABLE:
			paths.append_array(_packed(Character.NET_STATE_PATHS))
		WORLD_PROP:
			paths.append_array([
				":position",
				":rotation",
				":velocity",
			])
		CHARGE:
			paths.append_array(_packed(Character.NET_STATE_PATHS))
			paths.append_array([
				":net_phase",
				":net_telegraph",
				":_head_pitch",
				"Head:rotation",
				"Body:rotation",
			])
		COVER:
			paths.append_array([
				":position",
				":rotation",
				":home",
				":queued_home",
				":cover_t",
				":cover_dir",
				":has_queued",
			])
		PROJECTILE, VOLUME:
			paths.append_array([
				":position",
				":rotation",
				":_elapsed",
				":_age",
				":_finished",
				":_done",
				":_playing",
			])
		CORPSE:
			paths.append_array([
				":position",
				":rotation",
				":net_linear_velocity",
				":net_angular_velocity",
			])
	return paths


static func input_paths(profile: String) -> Array[String]:
	if profile == PLAYABLE:
		return PlayerNetInputScript.net_input_paths()
	return []


static func interpolate_paths(profile: String) -> Array[String]:
	var paths: Array[String] = []
	match profile:
		PLAYABLE:
			paths.append_array([
				":position",
				"Head:rotation",
				"Head/CameraPivot:rotation",
			])
		CHARGE:
			paths.append_array([
				":position",
				":rotation",
				"Head:rotation",
				"Body:rotation",
			])
		WORLD_PROP, PROJECTILE, VOLUME, COVER, CORPSE:
			paths.append_array([
				":position",
				":rotation",
			])
	return paths


## Local first-person: blend tick poses, but do not lerp look (mouse is frame-rate).
static func local_playable_interpolate_paths() -> Array[String]:
	return [":position"]


static func _packed(values: PackedStringArray) -> Array[String]:
	var paths: Array[String] = []
	for value in values:
		paths.append(value)
	return paths
