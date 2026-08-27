class_name TestEnv
extends RefCounted

## Headless unit-test runs are fully offline: no Steam client, no Steam API init,
## no network lobbies. Set FRIEND_SLOP_TEST=1 before Godot starts (run_checks.py / CI).
## LAN E2E also sets WIZARD_E2E=1 so the pit skips STT bootstrap.

const ENV_KEY := "FRIEND_SLOP_TEST"
const E2E_KEY := "WIZARD_E2E"


static func is_active() -> bool:
	return OS.get_environment(ENV_KEY) == "1"


static func is_e2e() -> bool:
	return OS.get_environment(E2E_KEY) == "1"


static func skip_match_voice() -> bool:
	return is_active() or is_e2e()
