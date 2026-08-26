@tool
class_name MonsterSense
extends Node

## Base for authored senses under Monster/Senses or Summon/Senses.
## Enabled senses append MonsterInterest candidates; Monster prefers among them.
## @tool so lookdev live AI can call append_interest_candidates in the editor.

## Off = this sense is ignored (gizmo hidden too). Tune range on the child node.
@export var enabled: bool = true


static func can_append_from(node: Node) -> bool:
	## Placeholder (non-@tool) instances list methods but cannot be called.
	if node == null or not is_instance_valid(node):
		return false
	if not node.has_method("append_interest_candidates"):
		return false
	if not Engine.is_editor_hint():
		return true
	var scr := node.get_script() as Script
	return scr == null or scr.is_tool()


func append_interest_candidates(_monster: CharacterBody3D, _out: Array) -> void:
	## Override in Hearing / LightAwareness / custom senses.
	pass
