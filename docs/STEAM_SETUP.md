# Steam multiplayer setup

Wizard uses the **GodotSteam editor**. Steam is compiled into that runner — do not install `addons/godotsteam`.

## Checklist

1. Install **Steam** and sign in.
2. Run the **GodotSteam editor** matching the pins in `tools/versions.env` (Godot 4.6.3 + GodotSteam 4.19.1).
3. Keep `steam_appid.txt` next to the game (repo root uses App ID **480** for editor play).
4. Host / join from the menu lobby.

Set `GODOT_EDITOR_WIN` in `tools/versions.env` to your GodotSteam editor `.exe` so Make uses the same binary.

## Two-account smoke test

1. Account A: **Host Game** → note **Lobby ID** or click **Invite**.
2. Account B: accept invite or paste Lobby ID → **Connect**.
3. Host clicks **Start Game**.

Local and LAN still work if Steam is not running.

## Export

Export from the GodotSteam editor (with GodotSteam templates). Copy `steam_appid.txt` into the export folder (replace `480` before shipping).

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| “Steam is not running” | Launch the Steam client |
| GodotSteam “already registered” | A leftover `addons/godotsteam` addon is loaded next to the editor. Delete that folder (keep only `README.txt` if present), fully quit Godot, reopen. |
