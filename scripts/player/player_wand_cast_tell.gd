class_name PlayerWandCastTell
extends RefCounted

## Remote charge seek + one-shot release/fizzle. Clips: weapon export, else wand default.


static func clip_for(wand: PlayerWand, phase: int, effect_id: String) -> StringName:
	var weapon := _weapon_for_effect(wand, effect_id)
	var from_weapon := _clip_on_weapon(weapon, phase)
	if from_weapon != &"":
		return from_weapon
	match phase:
		Player.CAST_PHASE_CHARGING:
			return wand.default_charge_clip
		Player.CAST_PHASE_RELEASING:
			return wand.default_release_clip
		Player.CAST_PHASE_FIZZLE:
			return wand.default_fizzle_clip
		_:
			return &""


static func apply_phase(wand: PlayerWand, phase: int, factor: float, effect_id: String) -> void:
	var clip := clip_for(wand, phase, effect_id)
	if phase == Player.CAST_PHASE_CHARGING:
		_seek_charge_pose(wand, factor)
		_try_play_clip(wand, clip, factor)
	elif phase != wand._replicated_phase:
		match phase:
			Player.CAST_PHASE_RELEASING:
				_play_release(wand, factor, clip)
			Player.CAST_PHASE_FIZZLE:
				_play_fizzle(wand, clip)
			Player.CAST_PHASE_IDLE:
				wand._snap_to_pre_click_pose()


static func _weapon_for_effect(wand: PlayerWand, effect_id: String) -> Node:
	if effect_id.is_empty():
		return null
	for child in wand.get_children():
		if child is NetSpellWeapon and str(child.get("effect_id")) == effect_id:
			return child
	return null


static func _clip_on_weapon(weapon: Node, phase: int) -> StringName:
	if weapon == null:
		return &""
	match phase:
		Player.CAST_PHASE_CHARGING:
			return weapon.get("charge_clip") as StringName
		Player.CAST_PHASE_RELEASING:
			return weapon.get("release_clip") as StringName
		Player.CAST_PHASE_FIZZLE:
			return weapon.get("fizzle_clip") as StringName
		_:
			return &""


static func _seek_charge_pose(wand: PlayerWand, factor: float) -> void:
	if wand._pose_tween != null and is_instance_valid(wand._pose_tween):
		wand._pose_tween.kill()
		wand._pose_tween = null
	var idle: Transform3D = wand._default_held_transform
	var charged: Transform3D = wand._cast_charge_transform(idle)
	wand.transform = idle.interpolate_with(charged, clampf(factor, 0.0, 1.0))


static func _try_play_clip(wand: PlayerWand, clip: StringName, seek_factor: float = -1.0) -> void:
	if clip == &"":
		return
	var anim := wand.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim == null or not anim.has_animation(clip):
		return
	anim.play(clip)
	if seek_factor >= 0.0:
		anim.seek(anim.current_animation_length * clampf(seek_factor, 0.0, 1.0), true)


static func _play_release(wand: PlayerWand, factor: float, clip: StringName) -> void:
	if clip != &"":
		_try_play_clip(wand, clip)
		return
	wand._start_p_shaped_wand_fx(clampf(factor, 0.0, 1.0))


static func _play_fizzle(wand: PlayerWand, clip: StringName) -> void:
	if clip != &"":
		_try_play_clip(wand, clip)
		return
	wand.play_fizzle(true)
