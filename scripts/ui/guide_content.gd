class_name GuideContent
extends RefCounted

## Pure text assembly for the Tab guide menu — unit-testable without UI nodes.

const SpellDefinitionScript := preload("res://scripts/spells/spell_definition.gd")

const EMPTY_OBJECTIVES := "No active objectives."
const CODEX_EMPTY_LIST_LABEL := "(No spells known yet)"


static func control_hints_text() -> String:
	return (
		"Move — WASD\n"
		+ "Dash — Shift · Jump — Space · Crouch — C\n"
		+ "Interact — F\n"
		+ "Cast — MMB raise wand & speak · LMB/RMB/Q/E assign or hold to fire\n"
		+ "Spellbook — [2] or B · Guide — Tab · Spells tab rearranges slots\n"
		+ "Broom — [1] · WASD fly · Space up · C down · Shift boost\n"
		+ "Summoning Book — [3] · Q/E turn pages · LMB select · Esc cancel"
	)


static func format_objective_lines(lines: PackedStringArray) -> String:
	if lines.is_empty():
		return EMPTY_OBJECTIVES
	return "\n".join(lines)


static func build_view(objective_lines: PackedStringArray) -> Dictionary:
	return {
		"hints": control_hints_text(),
		"objectives": format_objective_lines(objective_lines),
	}


static func codex_spell_ids(loadout: Node) -> Array[String]:
	if loadout == null or not loadout.has_method("get_known_spell_ids"):
		return []
	return loadout.get_known_spell_ids()


static func format_cooldown_countdown(remaining_sec: float) -> String:
	if remaining_sec <= 0.0:
		return ""
	## One decimal keeps long cooldowns readable without jittery whole-second jumps.
	return "Cooldown — %.1fs" % remaining_sec


static func codex_row_label(
	spell: SpellDefinitionScript,
	spell_id: String,
	remaining_cooldown_sec: float = 0.0
) -> String:
	var base := spell_id
	if spell != null:
		base = "%s — \"%s\"" % [spell.display_name, spell.get_incantation_text()]
	var countdown := format_cooldown_countdown(remaining_cooldown_sec)
	if countdown.is_empty():
		return base
	return "%s  ·  %s" % [base, countdown]


static func codex_empty_hint() -> String:
	return "Find floating tomes in the maze."


static func codex_list_hint() -> String:
	return "Click a spell to read more — [MMB] select by voice · hold slot key to cast."


static func build_spell_detail(
	spell: SpellDefinitionScript,
	remaining_cooldown_sec: float = 0.0
) -> Dictionary:
	if spell == null:
		return {"title": "Spell", "body": "No details available."}
	var lines := spell.get_codex_detail_lines()
	var countdown := format_cooldown_countdown(remaining_cooldown_sec)
	if not countdown.is_empty():
		var with_cd := PackedStringArray()
		with_cd.append(countdown)
		with_cd.append("")
		for line in lines:
			with_cd.append(line)
		lines = with_cd
	return {
		"title": spell.display_name,
		"body": "\n".join(lines),
	}
