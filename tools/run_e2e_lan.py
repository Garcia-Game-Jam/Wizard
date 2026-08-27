#!/usr/bin/env python3
"""Optional two-process LAN pit E2E. Not part of make test.

Usage: python tools/run_e2e_lan.py
"""

from __future__ import annotations

import os
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from restore_extensions import (  # noqa: E402
    disable_gdvosk_for_headless_tests,
    find_godot_binary,
    sync_extensions,
)

CACHE = ROOT / ".cache"
HOST_LOG = CACHE / "e2e-lan-host.log"
GUEST_LOG = CACHE / "e2e-lan-guest.log"
GDVOSK_CRASH_EXIT = 3221225477
GDVOSK_HEAP_CRASH_EXIT = 3221226356
GDVOSK_CRASH_EXIT_LINUX = 139
HOST_READY_SEC = 40.0
MATCH_SEC = 70.0


def _in_ci() -> bool:
    return os.environ.get("CI") == "true" or os.environ.get("GITHUB_ACTIONS") == "true"


def _editor_running(godot: Path | None) -> bool:
    if _in_ci():
        return False
    names: set[str] = {"godot", "godot.exe"}
    if godot is not None:
        names.add(godot.name.lower())
        names.add(godot.stem.lower())
    try:
        if sys.platform == "win32":
            proc = subprocess.run(
                ["tasklist"], capture_output=True, text=True, check=False
            )
            haystack = proc.stdout.lower()
            return any(name in haystack for name in names if name)
        proc = subprocess.run(
            ["pgrep", "-if", "godot"], capture_output=True, check=False
        )
        return proc.returncode == 0
    except OSError:
        return False


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def _ok_exit(code: int | None, text: str) -> bool:
    if code == 0:
        return True
    if code in (GDVOSK_CRASH_EXIT, GDVOSK_HEAP_CRASH_EXIT, GDVOSK_CRASH_EXIT_LINUX):
        return "E2E_OK" in text
    return False


_LOG_ALLOW = (
    "gdvosk.gdextension",
    "SettingsManager: saved input",
    "MIC_OR_ROUTE_SILENT",
)


def _unexpected_log_noise(text: str) -> list[str]:
    hits: list[str] = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        if any(allow in line for allow in _LOG_ALLOW):
            continue
        if line.startswith("ERROR:") or line.startswith("WARNING:"):
            hits.append(line)
            continue
        if line.startswith("[ERR]") or line.startswith("[WRN]"):
            hits.append(line)
    return hits[:12]


def _pump(proc: subprocess.Popen[str], bucket: list[str], log_path: Path) -> None:
    assert proc.stdout is not None
    with log_path.open("w", encoding="utf-8") as handle:
        for line in proc.stdout:
            handle.write(line)
            handle.flush()
            bucket.append(line)
            sys.stdout.write(line)
            sys.stdout.flush()


def _wait_line(bucket: list[str], needle: str, timeout: float) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if any(needle in line for line in bucket):
            return True
        time.sleep(0.05)
    return False


def _godot_cmd(godot: Path, role: str, port: int) -> list[str]:
    return [
        str(godot),
        "--headless",
        "--path",
        str(ROOT),
        "--audio-driver",
        "Dummy",
        "--script",
        "res://tests/e2e/lan_pit.gd",
        "--",
        f"--role={role}",
        f"--port={port}",
    ]


def main() -> int:
    godot = find_godot_binary()
    if godot is None:
        print(
            "Godot executable not found. Set GODOT_PATH or GODOT_EDITOR_WIN.",
            file=sys.stderr,
        )
        return 1
    if _editor_running(godot):
        print(
            "Close the Godot editor before LAN E2E (GDExtension/autoload conflict).",
            file=sys.stderr,
        )
        return 1

    port = _free_port()
    env = os.environ.copy()
    env["FRIEND_SLOP_TEST"] = "1"
    env["WIZARD_E2E"] = "1"
    env["STEAM_PROXIMITY_VOICE_TEST"] = "1"
    CACHE.mkdir(parents=True, exist_ok=True)
    host_out: list[str] = []
    guest_out: list[str] = []
    host: subprocess.Popen[str] | None = None
    guest: subprocess.Popen[str] | None = None
    disable_gdvosk_for_headless_tests()
    try:
        print(f"LAN E2E on 127.0.0.1:{port}")
        host = subprocess.Popen(
            _godot_cmd(godot, "host", port),
            cwd=str(ROOT),
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        threading.Thread(
            target=_pump, args=(host, host_out, HOST_LOG), daemon=True
        ).start()
        if not _wait_line(host_out, "E2E_HOST_LISTENING", HOST_READY_SEC):
            print("Host did not listen in time.", file=sys.stderr)
            return 1
        guest = subprocess.Popen(
            _godot_cmd(godot, "guest", port),
            cwd=str(ROOT),
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        threading.Thread(
            target=_pump, args=(guest, guest_out, GUEST_LOG), daemon=True
        ).start()
        deadline = time.monotonic() + MATCH_SEC
        while time.monotonic() < deadline:
            host_text = "".join(host_out)
            guest_text = "".join(guest_out)
            if "E2E_FAIL" in host_text or "E2E_FAIL" in guest_text:
                print("LAN E2E failed (see logs).", file=sys.stderr)
                return 1
            host_done = host.poll() is not None
            guest_done = guest.poll() is not None
            if host_done and guest_done:
                break
            time.sleep(0.1)
        else:
            print("LAN E2E timed out waiting for both peers.", file=sys.stderr)
            return 1
        host.wait(timeout=5)
        guest.wait(timeout=5)
        host_text = "".join(host_out)
        guest_text = "".join(guest_out)
        host_ok = _ok_exit(host.returncode, host_text) and "E2E_OK host" in host_text
        guest_ok = _ok_exit(guest.returncode, guest_text) and "E2E_OK guest" in guest_text
        noise = _unexpected_log_noise(host_text + "\n" + guest_text)
        if host_ok and guest_ok and not noise:
            print("LAN E2E passed.")
            return 0
        if noise:
            print("Unexpected errors/warnings:", file=sys.stderr)
            for line in noise:
                print(f"  {line}", file=sys.stderr)
        print(
            f"LAN E2E failed (host={host.returncode} guest={guest.returncode}).",
            file=sys.stderr,
        )
        return 1
    finally:
        for proc in (guest, host):
            if proc is not None and proc.poll() is None:
                proc.kill()
        sync_extensions(godot)


if __name__ == "__main__":
    raise SystemExit(main())
