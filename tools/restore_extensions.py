#!/usr/bin/env python3
"""Sync GDExtension manifests for the active Godot binary and test runs."""

from __future__ import annotations

import json
import os
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VERSIONS_ENV = ROOT / "tools" / "versions.env"
PROJECT_METADATA = ROOT / ".godot" / "editor" / "project_metadata.cfg"

GDVOSK_ACTIVE = ROOT / "addons" / "gdvosk" / "gdvosk.gdextension"
GDVOSK_DISABLED = ROOT / "addons" / "gdvosk" / "gdvosk.gdextension.disabled"
GODOTSTEAM_ACTIVE = ROOT / "addons" / "godotsteam" / "godotsteam.gdextension"
GODOTSTEAM_DISABLED = ROOT / "addons" / "godotsteam" / "godotsteam.gdextension.disabled"


def _read_versions_env(key: str) -> str:
	if not VERSIONS_ENV.exists():
		return ""
	for line in VERSIONS_ENV.read_text(encoding="utf-8").splitlines():
		stripped = line.strip()
		if not stripped or stripped.startswith("#") or "=" not in stripped:
			continue
		line_key, value = stripped.split("=", 1)
		if line_key.strip() == key:
			return value.strip()
	return ""


def _resolve_godot_executable(candidate: Path) -> Path | None:
	if candidate.is_file():
		return candidate
	if candidate.suffix.lower() == ".exe":
		console = candidate.with_name(f"{candidate.stem}_console{candidate.suffix}")
		if console.is_file():
			return console
	return None


def _cached_godot_candidates() -> list[Path]:
	version = _read_versions_env("GODOT_VERSION")
	if not version:
		return []
	cache_dir = ROOT / ".cache" / "godot"
	candidates: list[Path] = []
	if sys.platform == "win32":
		candidates.extend(
			[
				cache_dir / f"Godot_v{version}-stable_win64.exe",
				cache_dir / f"Godot_v{version}-stable_win64_console.exe",
			]
		)
	else:
		candidates.append(cache_dir / f"Godot_v{version}-stable_linux.x86_64")
	return candidates


def _godot_from_project_metadata() -> Path | None:
	## Last editor that opened this project — more accurate than a stale VS Code path.
	if not PROJECT_METADATA.exists():
		return None
	text = PROJECT_METADATA.read_text(encoding="utf-8")
	match = re.search(r'^executable_path="(.+)"\s*$', text, re.MULTILINE)
	if match is None:
		return None
	return _resolve_godot_executable(Path(match.group(1)))


def _godot_from_vscode_settings() -> Path | None:
	settings_path = ROOT / ".vscode" / "settings.json"
	if not settings_path.exists():
		return None
	data = json.loads(settings_path.read_text(encoding="utf-8"))
	editor_path = str(data.get("godotTools.editorPath", "")).strip()
	if not editor_path:
		return None
	return _resolve_godot_executable(
		Path(editor_path.replace("${workspaceFolder}", str(ROOT)))
	)


def find_godot_binary() -> Path | None:
	env_path = os.environ.get("GODOT_PATH", "").strip()
	if env_path:
		resolved = _resolve_godot_executable(Path(env_path))
		if resolved is not None:
			return resolved

	pinned_win = _read_versions_env("GODOT_EDITOR_WIN")
	if pinned_win:
		resolved = _resolve_godot_executable(Path(pinned_win))
		if resolved is not None:
			return resolved

	resolved = _godot_from_project_metadata()
	if resolved is not None:
		return resolved

	resolved = _godot_from_vscode_settings()
	if resolved is not None:
		return resolved

	for candidate in _cached_godot_candidates():
		resolved = _resolve_godot_executable(candidate)
		if resolved is not None:
			return resolved

	which_godot = shutil.which("godot")
	if which_godot:
		return Path(which_godot)
	return None


def _extension_uid(active: Path) -> Path:
	return active.with_suffix(".gdextension.uid")


def _disable_extension(active: Path, disabled: Path) -> bool:
	"""Ensure only the disabled manifest exists. Returns True if anything changed."""
	if not active.exists():
		return False
	uid_active = _extension_uid(active)
	uid_disabled = _extension_uid(disabled)
	if disabled.exists():
		active.unlink()
		if uid_active.exists():
			uid_active.unlink()
		return True
	active.rename(disabled)
	if uid_active.exists():
		if uid_disabled.exists():
			uid_active.unlink()
		else:
			uid_active.rename(uid_disabled)
	return True


def _enable_extension(active: Path, disabled: Path) -> bool:
	"""Ensure only the active manifest exists. Returns True if anything changed."""
	if not disabled.exists():
		return False
	uid_active = _extension_uid(active)
	uid_disabled = _extension_uid(disabled)
	if active.exists():
		disabled.unlink()
		if uid_disabled.exists():
			uid_disabled.unlink()
		return True
	disabled.rename(active)
	if uid_disabled.exists():
		if uid_active.exists():
			uid_disabled.unlink()
		else:
			uid_disabled.rename(uid_active)
	return True


def _restore_if_disabled(active: Path, disabled: Path) -> str | None:
	if _enable_extension(active, disabled):
		return str(active.relative_to(ROOT))
	return None


def sync_godotsteam_gdextension(godot: Path | None = None) -> list[str]:
	## Local play uses the GodotSteam editor. Never enable the GDExtension here.
	## CI release jobs install it on the runner and skip this helper.
	if os.environ.get("GITHUB_ACTIONS") == "true":
		return []
	if os.environ.get("FRIEND_SLOP_CI_STEAM", "").strip() == "1":
		return []
	changes: list[str] = []
	if _disable_extension(GODOTSTEAM_ACTIVE, GODOTSTEAM_DISABLED):
		changes.append(
			"Disabled leftover addons/godotsteam/godotsteam.gdextension. "
			+ "Steam comes from the GodotSteam editor, not this addon."
		)
	return changes


def disable_gdvosk_for_headless_tests() -> bool:
	"""Do not load libgdvosk in --script Godot. Unloading it on quit ACCESS_VIOLATIONs."""
	return _disable_extension(GDVOSK_ACTIVE, GDVOSK_DISABLED)


def sync_extensions(godot: Path | None = None) -> list[str]:
	changes: list[str] = []
	restored = _restore_if_disabled(GDVOSK_ACTIVE, GDVOSK_DISABLED)
	if restored is not None:
		changes.append(f"Restored {restored}")
	changes.extend(sync_godotsteam_gdextension(godot))
	return changes


def restore_extensions(godot: Path | None = None) -> list[str]:
	"""Back-compat alias for sync_extensions()."""
	return sync_extensions(godot)


def main() -> int:
	changes = sync_extensions(find_godot_binary())
	if changes:
		print("Synced GDExtension manifests:")
		for message in changes:
			print(f"  - {message}")
		print("Fully quit Godot, reopen the project, then run again.")
		return 0
	print("GDExtension manifests already match the active Godot binary.")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
