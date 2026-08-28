class_name Damage
extends Effect

## Spend HP. amount must be > 0 — omit this resource to deal no damage.

@export var amount: float = 1.0


static func with(hit_amount: float) -> Damage:
	var effect := Damage.new()
	effect.amount = hit_amount
	return effect


func apply(body: CharacterBody3D, from: Variant) -> void:
	if amount <= 0.0:
		push_error("Damage.amount must be > 0; omit Damage from the payload to skip HP")
		assert(amount > 0.0)
		return
	Character.apply_hit(body, amount, from)
