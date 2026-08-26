class_name SpellDefinition
extends Resource

## Drives slot-cast wand flourish (offensive jab, defensive guard, etc.).
enum Category { OFFENSIVE, DEFENSIVE, UTILITY, BUFF }
## CAST charges while the slot hotkey is held; CHANNEL is instantly ready.
enum CastMode { CAST, CHANNEL }
## Wand flourish used while charging / releasing a slotted spell.
enum WandFxKind { P_SHAPED, SHAKE, LIFT_DEFENSIVE }

const DEFAULT_ONE_WORD_DURATION_MS := 700
const SpellEffectSyncScript := preload("res://scripts/spells/spell_effect_sync.gd")
const SPELLS_ROOT := "res://scenes/spells/"
const CAST_GROWING_ORB := preload("res://scenes/spells/_shared/growing_orb_cast.tscn")

@export var id: String = ""
@export var display_name: String = ""
@export var incantation_words: PackedStringArray = PackedStringArray()
@export var syllable_cadence_ms: PackedInt32Array = PackedInt32Array()
@export var pitch_targets_hz: PackedFloat32Array = PackedFloat32Array()
@export var require_rhythm: bool = false
@export_range(0.0, 30.0, 0.05) var cooldown_sec: float = 8.0
## After this spell's ward shatters, multiply the next ward's regen delay by this.
@export_range(1.0, 8.0, 0.05) var shatter_regen_scale: float = 1.0
## Authored max HP for each new ward. Live HP lives on per-actor WardRuntime.
@export_range(0.0, 400.0, 1.0) var max_health: float = 0.0
## Seconds after the last cast before ward HP starts regenerating.
## Mirrored on scenes/spells/ward/ward.tscn (Ward root).
@export_range(0.0, 10.0, 0.05) var regen_delay_sec: float = 0.0
## Ward HP restored per second after regen_delay_sec.
@export_range(0.0, 50.0, 0.5) var regen_per_sec: float = 0.0
## 0 = no ammo bucket (cooldown-only). Flare uses a refillable magazine.
@export_range(0, 20, 1) var ammo_max: int = 0
## Seconds between ammo refills while below ammo_max. Ignored if ammo_max is 0.
@export_range(0.0, 30.0, 0.05) var ammo_refill_sec: float = 0.0
@export var effect_id: String = ""
## Hit damage applied when this spell connects. 0 = no HP damage (utility).
@export_range(0.0, 200.0, 1.0) var damage: float = 0.0
## Shared hue for mana bar, spell-word HUD, and cast / recognition FX.
@export var color: Color = Color(0.55, 0.28, 0.72, 1.0)
@export var category: Category = Category.UTILITY
@export var cast_mode: CastMode = CastMode.CAST
## Slot hold time before CAST spells are ready (CHANNEL uses 0).
@export_range(0.0, 10.0, 0.05) var charge_time_sec: float = 1.0
## If true, releasing before charge_time_sec completes fizzles instead of casting.
@export var require_full_charge := false
## Optional wand-tip charge animation. Empty uses <spell_dir>/cast.tscn.
@export var cast_charge_scene: PackedScene


func uses_ammo() -> bool:
	return ammo_max > 0


func requires_full_charge() -> bool:
	return require_full_charge and not is_channelled() and get_charge_time_sec() > 0.001


func get_display_color() -> Color:
	return color


func get_word_display_color() -> Color:
	return color


func is_channelled() -> bool:
	return cast_mode == CastMode.CHANNEL


func get_wand_fx_kind() -> WandFxKind:
	if category == Category.DEFENSIVE:
		return WandFxKind.LIFT_DEFENSIVE
	if is_channelled():
		return WandFxKind.SHAKE
	return WandFxKind.P_SHAPED


func get_cast_charge_scene() -> PackedScene:
	if cast_charge_scene != null:
		return cast_charge_scene
	var folder := _folder_name()
	if folder.is_empty():
		return CAST_GROWING_ORB
	var path := "%scast.tscn" % spell_folder(folder)
	if ResourceLoader.exists(path):
		return load(path) as PackedScene
	return CAST_GROWING_ORB


static func spell_folder(spell_id: String) -> String:
	if spell_id.is_empty():
		return SPELLS_ROOT
	return "%s%s/" % [SPELLS_ROOT, spell_id]


static func world_scene_path(spell_id: String) -> String:
	return "%s%s.tscn" % [spell_folder(spell_id), spell_id]


func _folder_name() -> String:
	if not id.is_empty():
		return id
	if effect_id == "flashlight_toggle":
		return "light"
	return effect_id


func get_charge_time_sec() -> float:
	if is_channelled():
		return 0.0
	if effect_id == "fireball":
		return FireballProjectile.authored_charge_time_sec()
	return maxf(charge_time_sec, 0.0)


func get_base_damage() -> float:
	if damage > 0.0:
		return damage
	if effect_id == "fireball":
		return FireballProjectile.DEFAULT_HIT_DAMAGE
	return 0.0


func get_fire_interval_sec() -> float:
	if uses_ammo() and ammo_refill_sec > 0.0:
		return ammo_refill_sec
	var charge := get_charge_time_sec()
	var cd := maxf(cooldown_sec, 0.0)
	if requires_full_charge():
		return maxf(charge, 0.05)
	if is_channelled():
		return maxf(cd, 0.05)
	return maxf(cd, charge) if cd > 0.0 or charge > 0.0 else 0.05


func get_incantation_text() -> String:
	return " ".join(incantation_words)


func word_count() -> int:
	return incantation_words.size()


func get_target_duration_sec() -> float:
	return float(get_target_duration_ms()) / 1000.0


func get_target_duration_ms() -> int:
	if syllable_cadence_ms.is_empty():
		return maxi(600, word_count() * 450)
	var last_ms: int = syllable_cadence_ms[syllable_cadence_ms.size() - 1]
	if word_count() == 1 and last_ms <= 0:
		return DEFAULT_ONE_WORD_DURATION_MS
	if last_ms <= 0:
		return DEFAULT_ONE_WORD_DURATION_MS
	return last_ms + 250


func get_timing_guide_text() -> String:
	if not require_rhythm or incantation_words.is_empty():
		return ""
	if syllable_cadence_ms.size() >= word_count() and word_count() > 1:
		var parts: PackedStringArray = []
		for i in word_count():
			var ms: int = syllable_cadence_ms[i]
			parts.append('"%s" at %.2fs' % [incantation_words[i], float(ms) / 1000.0])
		return "Beat: " + ", ".join(parts)
	return 'Say "%s" in about %.1fs' % [get_incantation_text(), get_target_duration_sec()]


func get_listen_coaching_text() -> String:
	if incantation_words.is_empty():
		return "Speak the incantation clearly when the mic bar appears."
	if not require_rhythm:
		return (
			'Say "%s" clearly at normal volume. '
			% get_incantation_text()
			+ "Take your time — timing does not matter."
		)
	var duration: float = get_target_duration_sec()
	if word_count() == 1:
		return (
			'Say "%s" once, clearly, in about %.1fs. '
			% [incantation_words[0], duration]
			+ "Aim for normal speaking volume — the mic bar should move."
		)
	return (
		'Say "%s" at a steady pace (~%.1fs total). '
		% [get_incantation_text(), duration]
		+ "Watch the mic bar while you speak."
	)


func get_tome_lesson_text() -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append(get_listen_coaching_text())
	var timing: String = get_timing_guide_text()
	if not timing.is_empty():
		parts.append(timing)
	return "\n".join(parts)


func get_pitch_guide_text() -> String:
	if pitch_targets_hz.is_empty():
		return ""
	var parts: PackedStringArray = []
	for i in pitch_targets_hz.size():
		var label := hz_to_note_label(pitch_targets_hz[i])
		if word_count() > 1 and i < word_count():
			parts.append('"%s" ~ %s' % [incantation_words[i], label])
		else:
			parts.append(label)
	return "Pitch: " + " → ".join(parts)


static func hz_to_note_label(hz: float) -> String:
	if hz <= 0.0:
		return "?"
	var names := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
	var midi := 69.0 + 12.0 * log(hz / 440.0) / log(2.0)
	var rounded := int(round(midi))
	var octave := int(floor(float(rounded) / 12.0)) - 1
	var name_idx := posmod(rounded, 12)
	return "%s%d (%.0f Hz)" % [names[name_idx], octave, hz]


func get_learned_confirmation_text() -> String:
	return (
		'"%s" is yours now.\n'
		% display_name
		+ "Hold [LMB], say the incantation, then release. [B] opens your spell codex."
	)


func get_cast_success_text() -> String:
	var text := "The spell takes effect."
	match effect_id:
		"light":
			text = "Smoke trails glow for several seconds."
		"haste":
			text = "You surge forward — movement speed increased!"
		"fireball":
			text = "A blazing fireball launches from your wand!"
		"flare":
			text = "A signal flare streaks toward your aim and bursts into a lasting beacon!"
		"ward":
			text = "A blue ward beam holds with your wand, then stays and fades."
		"flashlight_toggle":
			text = "Your wand light toggles."
		"light_ball":
			text = "An orb of light hangs in the air, then slowly fades."
		"target":
			text = "One object near your aim gains a dashed green outline."
		"pull":
			text = "The outlined object flies toward your gaze."
		"follow":
			text = "The outlined object drifts toward you along open paths."
		"stop":
			text = "Follow, Pull, and Target outlines dissolve for everyone."
		"dispell":
			text = "Target outlines, Follow, and light balls dissolve."
		"clone":
			text = (
				"A duplicate of the targeted light ball or relic appears beside it. "
				+ "Each object can be cloned only once."
			)
	return text


func get_codex_effect_detail() -> String:
	var text := get_cast_success_text()
	match effect_id:
		"light":
			text = (
				"Reveals recent player smoke trails for %.0f seconds."
				% SpellEffectSyncScript.DEFAULT_LIGHT_DURATION
			)
		"haste":
			text = (
				"Increases movement speed by %.0f%% for %.0f seconds."
				% [
					(SpellEffectSyncScript.DEFAULT_HASTE_MULTIPLIER - 1.0) * 100.0,
					SpellEffectSyncScript.DEFAULT_HASTE_DURATION,
				]
			)
		"fireball":
			text = (
				"Hold to charge a fireball at your wand tip, then release to launch. "
				+ "Let go early and it fizzles into a smoky wisp. "
				+ "Shots explode on impact and knock players back."
			)
		"flare":
			text = (
				"Say \"flare\" to form a red cone at your wand tip. A tiny spark "
				+ "rockets toward your crosshair and bursts into a lasting signal flare. "
				+ "You carry a limited flare bucket that refills over time."
			)
		"ward":
			text = (
				"Hold Ward to channel a blue beam from your wand; it follows while "
				+ "held. Release to leave the shield in place. It has a health pool, "
				+ "tints red as it weakens, and shatters when emptied. After one "
				+ "second it regenerates. No recast cooldown; a shatter doubles "
				+ "the next ward's regen delay."
			)
		"flashlight_toggle":
			text = (
				"Say \"light\" to turn your wand beam on or off. "
				+ "Cast again to flip the current state."
			)
		"light_ball":
			text = (
				"Say \"light ball\" to leave a glowing orb toward your crosshair. "
				+ "It fades away after %.0f seconds."
				% SpellEffectSyncScript.DEFAULT_LIGHT_BALL_DURATION
			)
		"target":
			text = (
				"Say \"target\" to outline the light orb, relic, or relic clone "
				+ "closest to your aim for %.0f seconds."
				% SpellEffectSyncScript.DEFAULT_TARGET_DURATION
			)
		"pull":
			text = (
				"While Target outlines are active, say \"pull\" to yank the "
				+ "object nearest your aim along the ground toward you — fast "
				+ "at first, then easing to a stop. Requires clear line of sight."
			)
		"follow":
			text = (
				"While Target outlines are active, say \"follow\" to send the "
				+ "looked-at object toward you along open paths at a brisk "
				+ "pace until Stop or Dispell."
			)
		"stop":
			text = (
				"Say \"stop\" to end Follow/Pull for all players and clear "
				+ "Target outlines. Does not destroy light balls."
			)
		"dispell":
			text = (
				"While Target outlines are active, say \"dispel\" to clear them, "
				+ "end Follow/Pull, and destroy a targeted light ball or relic clone."
			)
		"clone":
			text = (
				"While Target outlines are active, say \"clone\" to duplicate a "
				+ "targeted light ball or the relic once. Relic clones look real "
				+ "but cannot be picked up; Dispell destroys them. Clones and "
				+ "already-cloned objects cannot be cloned again."
			)
	return text


func get_codex_detail_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append('Incantation: "%s"' % get_incantation_text())
	lines.append("")
	lines.append("How to cast")
	lines.append(get_listen_coaching_text())
	var timing := get_timing_guide_text()
	if not timing.is_empty():
		lines.append(timing)
	var pitch := get_pitch_guide_text()
	if not pitch.is_empty():
		lines.append(pitch)
	lines.append("")
	lines.append("What it does")
	lines.append(get_codex_effect_detail())
	return lines
