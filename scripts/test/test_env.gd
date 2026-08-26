class_name TestEnv
extends RefCounted

## Headless unit-test runs are fully offline: no Steam client, no Steam API init,
## no network lobbies. Set FRIEND_SLOP_TEST=1 before Godot starts (run_checks.py / CI).

const ENV_KEY := "FRIEND_SLOP_TEST"


static func is_active() -> bool:
	return OS.get_environment(ENV_KEY) == "1"
