# Arena (locked)

The game is wizards in a pit: spells, movement, monsters, netcode. No maze, no authored campaign map, no puzzle spine.

## Session loop (rule of 3)

Three fights, then one shared spell, repeat until the party quits. Reset on leave — no account meta.

1. Same greybox pit every fight. Cover and spawn pads may move; the map does not.
2. Each fight is a **new encounter**: more monsters, a different mix, and/or a different pad/cover arrangement.
3. After the **third** fight, **everyone gets the same new spell**.
4. The next three fights are built so that spell is the clean answer (still a fight, not a puzzle room).
5. Spoken load-in into a free hotbar slot (or auto-assign if the bar is full).

Fights only change monsters and layout. Rewards only change what you can cast.

## Week-1 slice (playable, not polished)

Three scripted dumps → grant **Ward** → more charger/ember dumps. Starter kit is Stone Throw. Downed wizards limp until the stage clears, then stand up in the pit. Do not sculpt live monsters in the scene tree; see the greybox freeze in [AGENTS.md](../../AGENTS.md).

Boot: lobby Start loads [scenes/arena.tscn](../../scenes/arena.tscn) via `GameApp.MATCH_SCENE`. Host dumps from [scripts/arena/arena_encounters.gd](../../scripts/arena/arena_encounters.gd).

## How to test

```bash
python tools/run_checks.py --lint-only
```

Playable: boot lobby → pit. Raise wand, speak a spell, slot it, dump a fight.

| Ask after | Pass if |
|-----------|---------|
| Fights 1–3 | The three dumps feel different; nobody asks “which corridor” |
| After fight 3 | Both players got the **same** new spell without a shop |
| Fights 4–6 | You **wanted** the new spell; old spells still work |
| Die | Limp (3s beat after last kill, then staging); all-dead shows Defeated (stages / kills / deaths) |
| Quit | Next boot is a fresh kit (no leftover meta) |

Fail if you needed a tutorial, a second map, or a currency. Fail if fight 4 is a copy of fight 1 with a new icon.

## Rewind vs death

`Character.current_health` is rewindable. Crossing to 0 still runs death teardown (capsule limp on the same tick path as living motion). Crossing back above 0 must reverse it (`Character.revived` → `restore_after_revive`). Do not mutate `RollbackSynchronizer` properties on death — that drops history subjects. Do not `queue_free` a dump body whose HP can return this tick — `_clear_monsters` (next dump) is the despawn. After the last live monster dies, wait 3s before staging. Players stay down until `rpc_stage_between` or host `rpc_game_over`. Cover and telegraph enroll before `NetworkTime.start()`. Dump children use stable names (`M{encounter}_{slot}`), not scene-root names.

### What not to test yet

New art, navmesh rewrite, UI restyle, PvP ladder, wave-as-campaign UI.
