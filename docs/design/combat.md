# Combat

Connect (who) then apply (what). A hit is a list of effect Resources. `Character.apply` does not switch on damage vs knock vs burn.

## Scene tree as source of truth

The **wand** is the gun (`NetSpellWeapon` children under `player_wand.tscn`, launch from authored `CastOrigin` toward the crosshair). The projectile scene is [`SpellProjectile`](../../scripts/spells/spell_projectile.gd): motion exports, mesh/look, `impact_fx` PackedScene, and payload are authored on that scene. `bind_player` only `configure()`s weapon nodes that already exist — it does not `NetSpellWeapon.new()`. There is no `spawn_predicted` `effect_id` switch for fireball or stone throw; `_spawn()` instantiates the weapon’s packed scene.

Flare is EPHEMERAL but not a `SpellProjectile` (it slides, then becomes a beacon).

## Connect vs apply

**Connect** names bodies. **Apply** spends the payload list on each one.

| Connect | When | Who |
|---------|------|-----|
| Projectile overlap | Stop pose | Every combat body whose authored capsule overlaps the flying `hit_radius` sphere (caster skipped). Group `corpse` gets **Knock only**. |
| Tick overlap | Every tick in a volume | `Area3D` overlapping bodies (ember trail, halo) |
| Direct | One named body | Charger ram |

No piercing. The ball stops on first world contact (`cast_motion` vs pit geometry) or when the overlap set is non-empty. Timeout and ward stop with **no payload and no impact FX**. World-only stop still plays `impact_fx`.

`hit_radius` is the flying ball. Floor gameplay `hit_radius` (~0.16 m) so tap-fire is not a 4 cm sphere. A large sphere can overlap a wall and a pawn in the same step: the wall stops travel, every overlapping pawn still gets the payload. Bodies the sphere never overlapped are not hits — there is no post-collision burst.

Pawn overlaps use authored `CollisionShape3D` at **node poses**, not `direct_space_state` capsules. Rewind pawns skip engine physics; the pit is what the physics snapshot can see.

Catch-up (`simulate_from_tick`) **may** apply payload once. Do not also apply on a later tick of a finished projectile.

## Payload

[`CombatPayload`](../../scripts/combat/combat_payload.gd) holds `@export var effects: Array[Resource] = []` (Effect subclasses). Membership in that array is the only opt-in. A `Knock` or `Stun` with a zero vector is authoring misuse (debug assert), not a silent skip. Same for `Damage` amount 0, `Burn` dps/duration 0, `Speed` with `mult == 1`.

Status Resources live under [`scripts/combat/effects/`](../../scripts/combat/effects/). Plumbing keeps the `Combat` prefix so it does not collide with groups or the player `Stun` **node**.

`Character.apply(from, payload)` loops `effect.apply(self, from)`. Array order is apply order. Empty list = nothing.

| Resource | Applies through |
|----------|-----------------|
| `Damage` | `Character.apply_hit` |
| `Knock` | `Character.apply_knockback` (charger/rat overrides still run) |
| `Stun` | Player child `Stun` (`PlayerStun`). Resource `class_name Stun` is not that node. |
| `Burn` | Character rewind fields, ticked as DPS |
| `Speed` | Character rewind fields (`mult < 1` slow, `> 1` haste) |

New status = new file in `effects/` + append to the list. No new branch on Character.

## Host and rewind

Damage and knock no-op unless `is_multiplayer_authority()` — same gates as today. Stun reuses `PlayerStun.begin_charger_hit` / `rpc_begin_charger_hit` (host can RPC the owning peer). Do not add a combat RPC bus, knock RPCs, or guest-inferred hits.

Slow and burn are Character rewind fields, enrolled in `Character.NET_STATE_PATHS` like HP. Do not add or remove `RollbackSynchronizer.state_properties` at apply time.

Player projectiles are **not** rewind bodies. They fly on Godot physics frames. Payload apply is queued on the victim and spent in that tick's `_rollback_tick` so restore does not drop HP/knock. `NetLiveness.after_spawn` is not the player-projectile door (it remains tick motion for volumes / threats that still use it).

## Two spawn doors

Player fireball and stone throw spawn through NetworkWeapon (caster-predicted, authored wand weapons) — including solo, when the tick clock is off. Ember threats spawn through `NetLiveness.replicate_world_fx` (guest copies are visual-only). Do not merge those doors. Combat is shared (overlap connect + payload); monster projectiles may extend `SpellProjectile` for flight/connect only.

## Adding a projectile

1. Authored scene extends [`SpellProjectile`](../../scripts/spells/spell_projectile.gd). Subclass look, charge, or a custom velocity — not connect, payload spend, or spawn RPCs.
2. Player spell: authored `NetSpellWeapon` under the wand with `projectile_scene`. Add `effect_id` to `SpellSyncLane.BY_EFFECT` as `EPHEMERAL`. `bind_player` only `configure()`s that node.
3. Monster threat: spawn through `NetLiveness.replicate_world_fx`. Override velocity, then call `_advance_and_connect`. Guest copies stay `visual_only`.
4. Do not add a `spawn_predicted` match, `NetLiveness.after_spawn`, or a new `SpellEffectSync.apply` spawn for a `SpellProjectile`.

## Live lists

- Fireball — `[Damage]`
- Stone throw — `[Damage, Knock]` (`from_impact`: impulse rebuilt per body from the impact point)
- Ember lob — `[Damage]`
- Ember trail — `[Burn, Speed]` (tick overlap)
- Ember halo — `[Speed]`
- Charger ram — `[Damage, Knock, Stun]`

Ward is connect-side (`SpellWardBlock`), not a payload entry.

## Do not

- Post-collision burst / feet-distance scan around the impact point
- Treat ZERO as skip, or restore a bag of payload args
- Effect registry / ECS
- Stun nodes on monsters (ram only hits players; missing `Stun` child = skip)
- Hurt-hop (knock on any HP loss)
- Mutate rewind property lists on death or apply
- `OmniLight3D.new()` / extra colliders in combat scripts
- Homing / live retarget, impact or animation RPCs, or `spawn_predicted` match tables for fireball/stone
