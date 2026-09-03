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

Three scripted dumps → grant **Ward** → more charger/ember dumps. Starter kit is Stone Throw. Downed wizards become a flying ghost (same pit collision, not a combat target) and leave a shoveable ragdoll; stage clear stands them at the pad at full HP. Do not sculpt live monsters in the scene tree; see the greybox freeze in [AGENTS.md](../../AGENTS.md).

Boot: lobby Start rolls a **level** uniformly at random from [scripts/arena/level_catalog.gd](../../scripts/arena/level_catalog.gd) (every `LevelDefinition` `.tres` under `scenes/arenas/levels/`) — rolled once by the host/solo player in `NetworkManager.start_game()` and shipped to every peer via the same RPC as the run seed, so nobody re-rolls independently. A level pins both its map (`LevelDefinition.map_id`, resolved through [scripts/arena/arena_catalog.gd](../../scripts/arena/arena_catalog.gd) same as before) and its own encounter sequence — Dev Settings' "Random level" toggle / "Level" dropdown replaced the old per-map picker outright, since map selection alone no longer means anything separate from level selection. `GameApp.MATCH_SCENE` is only the fallback for editor preview.

`scenes/arenas/levels/default_level.tres` (map `pit`) is [scripts/arena/arena_encounters.gd](../../scripts/arena/arena_encounters.gd)'s original hardcoded 6-entry table, converted losslessly — `arena_scene.gd` drives fights from whichever `LevelDefinition` `GameState.selected_level_id` resolves to (`_resolve_dump`/`_resolve_cover_positions` in `arena_scene.gd`), falling back to the classic `arena_encounters.gd` table only if no level resolves at all. Custom levels skip the pad/gate telegraph pre-show (their monsters spawn at free positions, not fixed pad indices — there's no pad to light up) and always restage cover to match each encounter's own authored obstacle layout; `cover_root`'s fixed StaticBody3D count caps how many obstacles actually show up per encounter (3 today) regardless of how many an encounter's `obstacle_positions` lists.

Authoring tool: [scenes/arenas/encounter_design_workshop.tscn](../../scenes/arenas/encounter_design_workshop.tscn) (open it in the Godot editor, not in-game) builds a `LevelDefinition` — a map id plus an ordered list of encounters, each with free-placed, kind-switchable monster spawns and cover obstacle positions — previewed live against the real arena geometry, with New/Load/Save/Save As on its `Level` field's own Inspector picker. Adding a map to `ArenaCatalog.MAPS` still just needs the same spawning contract as `arena.tscn` (see `arena_scene.gd`'s `@onready` node lookups); a level for it is then whatever gets authored/saved in the workshop.

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
| Die | Ghost + ragdoll (3s beat after last kill, then staging); all-dead shows Defeated (stages / kills / deaths) |
| Quit | Next boot is a fresh kit (no leftover meta) |

Fail if you needed a tutorial, a second map, or a currency. Fail if fight 4 is a copy of fight 1 with a new icon.

## Rewind vs death

`Character.current_health` is rewindable. Crossing to 0 still runs death teardown (players fly as a ghost on the same tick path as living motion; monsters limp). Crossing back above 0 must reverse it (`Character.revived` → `restore_after_revive`). Do not mutate `RollbackSynchronizer` properties on death — that drops history subjects. Do not `queue_free` a dump body whose HP can return this tick — `_clear_monsters` (next dump) is the despawn. After the last live monster dies, wait 3s before staging. `rpc_stage_between` stands ghosts at the pad on the movement tick (HP full first, so a late death does not drop a ragdoll there). `commit_pose` is the dump-pad snap, one tick. Players stay down until that RPC or host `rpc_game_over`. Cover and telegraph enroll before `NetworkTime.start()`. Dump children use stable names (`M{encounter}_{slot}`), not scene-root names.

### What not to test yet

New art, navmesh rewrite, UI restyle, PvP ladder, wave-as-campaign UI.
