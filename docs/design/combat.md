# Combat

Connect (who) then apply (what). A hit is a list of effect Resources. `Character.apply` does not switch on damage vs knock vs burn.

## Connect vs apply

**Connect** names bodies. **Apply** spends the payload list on each one.

| Connect | When | Who |
|---------|------|-----|
| Splash | One detonate | Combat groups within `splash_radius` of the impact point (root distance) |
| Tick overlap | Every tick in a volume | `Area3D` overlapping bodies (ember trail, halo) |
| Direct | One named body | Charger ram |

No piercing multi-hit. Timeout and ward stop the projectile with **no splash**.

`hit_radius` is the flying ball — when to stop (`PhysicsServer3D.cast_motion`). `splash_radius` is who gets the payload after stop. Do not use `Area3D.get_overlapping_bodies()` at detonate: the rollback overlap cache is a frame behind, and a capsule sits above the pawn root so a tight sphere misses.

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

## Two spawn doors

Player fireball and stone throw spawn through NetworkWeapon (caster-predicted). Ember threats spawn through `NetLiveness.replicate_world_fx`. Do not merge those doors. After spawn, both already call `NetLiveness.after_spawn`. Combat is shared (`CombatSplash` + payload); flight stays per scene. NetworkWeapon `simulate_from_tick` is pose catch-up only — it must not apply the payload; `_rollback_tick` / `_physics_process` apply once.

## Live lists

- Fireball — `[Damage]`
- Stone throw — `[Damage, Knock]` (`from_impact`: impulse rebuilt per body from the impact point)
- Ember lob — `[Damage]`
- Ember trail — `[Burn, Speed]` (tick overlap)
- Ember halo — `[Speed]`
- Charger ram — `[Damage, Knock, Stun]`

Ward is connect-side (`SpellWardBlock`), not a payload entry.

## Do not

- Shared projectile parent class
- Splash with Area3D overlap at detonate
- Treat ZERO as skip, or restore a bag of payload args
- Effect registry / ECS
- Stun nodes on monsters (ram only hits players; missing `Stun` child = skip)
- Hurt-hop (knock on any HP loss)
- Mutate rewind property lists on death or apply
- `OmniLight3D.new()` / extra colliders in combat scripts
