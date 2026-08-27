class_name CombatPayload
extends Resource

## List of effects applied in order by Character.apply. Membership is the opt-in.
## Array[Resource] (not Array[Effect]): typed Effect races class registration
## when this file loads before effects/effect.gd.

@export var effects: Array[Resource] = []
