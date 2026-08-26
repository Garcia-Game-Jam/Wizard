class_name SpellSyncLane
extends RefCounted

## Multiplayer persistence model for spell visuals / world effects.
## Pick one lane when adding a spell — do not invent a fourth replication style.
##
## PLAYER_BOUND — runs on the caster avatar (haste, flashlight). Wire carries
##   scalars only; every peer applies to that caster player node.
##
## EPHEMERAL — fire-and-forget projectile or short FX (fireball, ward). Pack spawn
##   pose into the cast wire; every peer spawns and simulates locally. No spawn_id,
##   no later remove/flicker RPC. Child impact VFX ride the local sim.
##   Use SpellEphemeralFx.
##
## WORLD_OBJECT — lasting interactive prop (light ball). Cast wire
##   spawns with a stable id; later Target / Dispell / touch events use
##   SpellWorldSync. Mutate and despawn go through the shared world-event RPC.
##
## TARGETED — operates on an existing world object or mark (target, pull, follow,
##   stop, dispell). Wire carries kind + mark / spawn_id / grid; apply resolves the
##   object on each peer. Despawn of world objects still uses SpellWorldSync.
##   Stop is payload-free and clears Follow/Pull on every peer.

const PLAYER_BOUND := "player_bound"
const EPHEMERAL := "ephemeral"
const WORLD_OBJECT := "world_object"
const TARGETED := "targeted"

## effect_id → lane. Keep in sync when registering a new spell effect.
const BY_EFFECT := {
	"haste": PLAYER_BOUND,
	"flashlight_toggle": PLAYER_BOUND,
	"fireball": EPHEMERAL,
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


static func is_known(effect_id: String) -> bool:
	return BY_EFFECT.has(effect_id)


static func describe(lane: String) -> String:
	match lane:
		PLAYER_BOUND:
			return "Apply on caster; scalars only; no world spawn id."
		EPHEMERAL:
			return "Spawn once from cast pose; local sim; no later events."
		WORLD_OBJECT:
			return "Spawn with id via SpellWorldSync; later mutate/despawn events."
		TARGETED:
			return "Resolve world mark/id; may clear or destroy SpellWorldSync objects."
		_:
			return "Unknown spell sync lane."
