class_name MonsterComboStep
extends Resource

## One step in a caster monster combo pattern.

enum StepType { INSTANT, CHARGE_THROW, CHARGE_HOLD }

@export var ability_id: String = ""
@export var step_type: StepType = StepType.CHARGE_THROW
@export_range(0.0, 5.0, 0.05) var delay_after_prev_sec: float = 0.0
## Extra combo hint for the ability (e.g. dash "close" / "away").
@export var combo_variant: String = ""
