#!/usr/bin/env python3
"""Install Blender MCP for Cursor (uv + addon + .cursor/mcp.json).

Run from repo root: python tools/setup_blender_mcp.py
Or: make setup-blender

After this: enable the addon in Blender, Start MCP Server (N → MCP tab),
then fully quit and relaunch Cursor.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MCP_JSON = ROOT / ".cursor" / "mcp.json"
UV_INSTALL_WIN = "irm https://astral.sh/uv/install.ps1 | iex"
UV_INSTALL_UNIX = "curl -LsSf https://astral.sh/uv/install.sh | sh"


def _uv_bin_dirs() -> list[Path]:
    home = Path.home()
    dirs = [
        home / ".local" / "bin",
        home / ".cargo" / "bin",
    ]
    if sys.platform == "win32":
        local = os.environ.get("LOCALAPPDATA")
        if local:
            dirs.insert(0, Path(local) / "uv")
    return dirs


def _which(name: str) -> str | None:
    found = shutil.which(name)
    if found:
        return found
    exe = f"{name}.exe" if sys.platform == "win32" else name
    for directory in _uv_bin_dirs():
        candidate = directory / exe
        if candidate.is_file():
            return str(candidate)
    return None


def _ensure_path_for_uv() -> None:
    parts = os.environ.get("PATH", "").split(os.pathsep)
    for directory in _uv_bin_dirs():
        d = str(directory)
        if directory.is_dir() and d not in parts:
            os.environ["PATH"] = d + os.pathsep + os.environ.get("PATH", "")


def ensure_uv() -> str:
    _ensure_path_for_uv()
    uv = _which("uv")
    if uv:
        return uv

    print("uv not found; installing via official installer...")
    if sys.platform == "win32":
        subprocess.run(
            ["powershell", "-ExecutionPolicy", "Bypass", "-Command", UV_INSTALL_WIN],
            check=True,
        )
    else:
        subprocess.run(["bash", "-lc", UV_INSTALL_UNIX], check=True)

    _ensure_path_for_uv()
    uv = _which("uv")
    if not uv:
        raise SystemExit(
            "uv installed but not on PATH. Open a new terminal, or add "
            f"{_uv_bin_dirs()[0]} to your user PATH, then re-run."
        )
    return uv


def ensure_uv_on_user_path() -> None:
    """GUI apps (Cursor) need uvx on the *user* PATH, not just this shell."""
    if sys.platform != "win32":
        return
    local_bin = str(Path.home() / ".local" / "bin")
    user_path = os.environ.get("Path") or os.environ.get("PATH") or ""
    # Prefer reading the persistent User PATH from the registry via PowerShell.
    try:
        raw = subprocess.check_output(
            [
                "powershell",
                "-NoProfile",
                "-Command",
                "[Environment]::GetEnvironmentVariable('Path', 'User')",
            ],
            text=True,
        ).strip()
    except subprocess.CalledProcessError:
        raw = user_path
    parts = [p for p in raw.split(";") if p]
    if local_bin in parts:
        return
    parts.append(local_bin)
    new_path = ";".join(parts)
    subprocess.run(
        [
            "powershell",
            "-NoProfile",
            "-Command",
            f"[Environment]::SetEnvironmentVariable('Path', '{new_path}', 'User')",
        ],
        check=True,
    )
    print(f"Added {local_bin} to user PATH (relaunch Cursor after setup)")


def mcp_server_entry() -> dict:
    # Pin 3.11 + managed interpreters to avoid conda/pyenv fights (upstream docs).
    env = {
        "UV_PYTHON_PREFERENCE": "only-managed",
        "BLENDER_HOST": "localhost",
        "BLENDER_PORT": "9876",
    }
    if sys.platform == "win32":
        # cmd wrapper so Cursor finds uvx after user PATH includes ~/.local/bin.
        return {
            "command": "cmd",
            "args": ["/c", "uvx", "--python", "3.11", "blender-mcp"],
            "env": env,
        }
    return {
        "command": "uvx",
        "args": ["--python", "3.11", "blender-mcp"],
        "env": env,
    }


def write_mcp_json() -> None:
    MCP_JSON.parent.mkdir(parents=True, exist_ok=True)
    data: dict = {"mcpServers": {}}
    if MCP_JSON.is_file():
        try:
            data = json.loads(MCP_JSON.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            raise SystemExit(f"Invalid JSON in {MCP_JSON}: {exc}") from exc
        if not isinstance(data.get("mcpServers"), dict):
            data["mcpServers"] = {}

    data["mcpServers"]["blender"] = mcp_server_entry()
    MCP_JSON.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {MCP_JSON.relative_to(ROOT)}")


def install_addon(_uv: str) -> None:
    uvx = _which("uvx")
    if uvx:
        run = [uvx, "--python", "3.11", "blender-mcp", "install-addon"]
    else:
        run = [_uv, "tool", "run", "--python", "3.11", "blender-mcp", "install-addon"]
    print("Installing Blender addon:", " ".join(run))
    env = os.environ.copy()
    env["UV_PYTHON_PREFERENCE"] = "only-managed"
    # blender-mcp prints Unicode arrows; Windows cp1252 consoles crash without this.
    env["PYTHONUTF8"] = "1"
    env["PYTHONIOENCODING"] = "utf-8"
    subprocess.run(run, check=True, cwd=ROOT, env=env)


def verify() -> int:
    _ensure_path_for_uv()
    ok = True
    if not _which("uvx") and not _which("uv"):
        print("FAIL: uv/uvx not found")
        ok = False
    else:
        print(f"OK: uv={_which('uv') or '?'} uvx={_which('uvx') or '?'}")

    if not MCP_JSON.is_file():
        print(f"FAIL: missing {MCP_JSON.relative_to(ROOT)} (run: make setup-blender)")
        ok = False
    else:
        data = json.loads(MCP_JSON.read_text(encoding="utf-8"))
        blender = (data.get("mcpServers") or {}).get("blender")
        if not blender:
            print("FAIL: .cursor/mcp.json has no blender server")
            ok = False
        else:
            print("OK: .cursor/mcp.json has blender MCP entry")

    if ok:
        print(
            "Blender MCP files OK.\n"
            "Still required in Blender: enable 'MCP for Blender', then "
            "N → MCP tab → Start MCP Server. Fully quit + relaunch Cursor."
        )
        return 0
    return 1


def main() -> int:
    if "--verify" in sys.argv:
        return verify()

    os.chdir(ROOT)
    uv = ensure_uv()
    print(f"Using uv: {uv}")
    ensure_uv_on_user_path()
    write_mcp_json()
    install_addon(uv)
    print(
        "\nNext steps:\n"
        "  1. Open Blender → Edit → Preferences → Add-ons\n"
        "  2. Enable 'Interface: MCP for Blender' (search MCP)\n"
        "  3. 3D View: press N → MCP for Blender → Start MCP Server\n"
        "  4. Fully quit Cursor (tray) and relaunch this project\n"
        "  5. In Agent chat: ask to list objects in the Blender scene\n"
        "\nCheck anytime: make verify-blender"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
