class_name SpellSyncLane
extends RefCounted

## Multiplayer persistence model for spell visuals / world effects.
## Pick one lane when adding a spell — do not invent a fourth replication style.
## NetWorldEvent maps each lane onto a netfox primitive (weapon / action / world_prop).
##
## PLAYER_BOUND — caster avatar (haste, flashlight). RewindableAction; scalars
##   live in host-owned playable state.
##
## EPHEMERAL — fire-and-forget projectile or volume (fireball, flare, ward).
##   NetworkWeapon: spawn immediately on the caster, host confirms, reconcile.
##   PredictiveSynchronizer + liveness; no queue_free in the tick loop.
##
## WORLD_OBJECT — lasting interactive prop (light ball). Host-owned rewindable
##   world_prop; later Target / Dispell / touch use SpellWorldSync ids.
##
## TARGETED — operates on an existing world object or mark (target, pull, follow,
##   stop, dispell, clone). Host-validated session RPC then apply; clone/prop
##   ids go through SpellWorldSync. Stop is payload-free and clears Follow/Pull.

const PLAYER_BOUND := "player_bound"
const EPHEMERAL := "ephemeral"
const WORLD_OBJECT := "world_object"
const TARGETED := "targeted"

## effect_id → lane. Adding a spell: pick a lane here. Predicted casts also
## need spawn_predicted() (ephemeral) or apply() (player-bound). Session RPC
## lanes only need apply(); world objects attach in their spawn().
const BY_EFFECT := {
	"haste": PLAYER_BOUND,
	"flashlight_toggle": PLAYER_BOUND,
	"fireball": EPHEMERAL,
	"stone_throw": EPHEMERAL,
	"flare": EPHEMERAL,
	"ward": EPHEMERAL,
	"light_ball": WORLD_OBJECT,
	"target": TARGETED,
	"pull": TARGETED,
	"follow": TARGETED,
	"stop": TARGETED,
	"dispell": TARGETED,
	"clone": TARGETED,
}


static func for_effect(effect_id: String) -> String:
	return str(BY_EFFECT.get(effect_id, ""))


## Fire-and-forget and caster-bound casts skip the session RPC and run on the tick.
static func predicts_locally(effect_id: String) -> bool:
	var lane := for_effect(effect_id)
	return lane == EPHEMERAL or lane == PLAYER_BOUND


## Child name on the playable for predicted casts. Empty = no per-player node.
static func player_node_name(effect_id: String) -> String:
	var lane := for_effect(effect_id)
	var base := effect_id.to_pascal_case()
	match lane:
		EPHEMERAL:
			return "%sWeapon" % base
		PLAYER_BOUND:
			return "%sAction" % base
		_:
			return ""


static func is_known(effect_id: String) -> bool:
	return BY_EFFECT.has(effect_id)


static func describe(lane: String) -> String:
	match lane:
		PLAYER_BOUND:
			return "RewindableAction on caster; host-owned pose state."
		EPHEMERAL:
			return "NetworkWeapon: predict spawn, host confirm, liveness."
		WORLD_OBJECT:
			return "Host-owned rewindable world_prop; later mutate/despawn by id."
		TARGETED:
			return "Host-validated apply; may clear or destroy SpellWorldSync objects."
		_:
			return "Unknown spell sync lane."
