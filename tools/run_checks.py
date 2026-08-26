#!/usr/bin/env python3
"""Run gdlint, GDScript analyzer warnings, and Godot unit tests.

Exit 0 on success, 1 on failure.
"""

from __future__ import annotations

import argparse
import atexit
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from check_gdscript_warnings import run_warning_probe  # noqa: E402
from restore_extensions import find_godot_binary, sync_extensions  # noqa: E402
LINT_PATHS = ("scripts",)
## Calls that write a theme override, and so re-emit NOTIFICATION_THEME_CHANGED.
UI_OVERRIDE_WRITE_MARKERS = ("add_theme_", "remove_theme_", "UiPalette.paint_")
TEST_LOG = ROOT / ".cache" / "godot-tests.log"
GDVOSK_GDEXTENSION = ROOT / "addons" / "gdvosk" / "gdvosk.gdextension"
GDVOSK_GDEXTENSION_DISABLED = ROOT / "addons" / "gdvosk" / "gdvosk.gdextension.disabled"
# Headless Godot may crash while unloading gdvosk on exit (Windows access violation,
# Linux segfault). Treat that as success when the test log reports all tests passed.
GDVOSK_CRASH_EXIT = 3221225477
GDVOSK_HEAP_CRASH_EXIT = 3221226356  # 0xC0000374 — seen on Windows headless shutdown
GDVOSK_CRASH_EXIT_LINUX = 139
# Godot editor/analyzer warnings gdlint does not cover — fail CI when seen in test output.
GDSCRIPT_ANALYZER_ERRORS = (
    "SHADOWED_GLOBAL_IDENTIFIER",
    "SHADOWED_VARIABLE",
    "SHADOWED_VARIABLE_BASE_CLASS",
    "UNUSED_PRIVATE_CLASS_VARIABLE",
    "REDUNDANT_AWAIT",
    "NARROWING_CONVERSION",
    "UNUSED_SIGNAL",
)
GDVOSK_EDITOR_LIBRARY_KEYS = (
    "windows.editor.x86_64",
    "windows.editor.x86_32",
    "linux.editor.x86_64",
    "macos.editor",
)


def _ensure_extensions_synced() -> None:
    """Keep GDExtension manifests aligned with the active Godot binary."""
    sync_extensions(find_godot_binary())


atexit.register(_ensure_extensions_synced)


def _validate_gdvosk_manifest() -> str | None:
    path = GDVOSK_GDEXTENSION
    if not path.exists():
        return None
    text = path.read_text(encoding="utf-8")
    missing = [key for key in GDVOSK_EDITOR_LIBRARY_KEYS if f"{key} =" not in text]
    if not missing:
        return None
    return (
        "gdvosk.gdextension is missing editor library entries: "
        + ", ".join(missing)
        + ". Re-run make setup-voice."
    )


def _find_gdscript_analyzer_issues(output: str) -> list[str]:
    issues: list[str] = []
    reload_keywords = (
        "shadowing",
        "same name as a built-in",
        "same name as a global class",
        "never used in the class",
        "never explicitly used",
        "Narrowing conversion",
        "unnecessary because",
    )
    for line in output.splitlines():
        if "<GDScript Error>" in line:
            for code in GDSCRIPT_ANALYZER_ERRORS:
                if code in line:
                    issues.append(line.strip())
                    break
            continue
        if "GDScript::reload" in line and any(key in line for key in reload_keywords):
            issues.append(line.strip())
    return issues


def _normalize_test_exit(returncode: int, stdout: str, stderr: str) -> int:
    combined = f"{stdout}\n{stderr}"
    if returncode == 0:
        return 0
    if "All tests passed." in combined and returncode in (
        GDVOSK_CRASH_EXIT,
        GDVOSK_HEAP_CRASH_EXIT,
        GDVOSK_CRASH_EXIT_LINUX,
        -GDVOSK_CRASH_EXIT_LINUX,
        -GDVOSK_CRASH_EXIT,
        -GDVOSK_HEAP_CRASH_EXIT,
    ):
        return 0
    if "test(s) failed." in combined or "  FAIL:" in combined:
        return 1
    return returncode


def _venv_scripts_dir() -> Path | None:
    if sys.platform == "win32":
        candidate = ROOT / ".venv" / "Scripts"
    else:
        candidate = ROOT / ".venv" / "bin"
    return candidate if candidate.is_dir() else None


def _project_python() -> Path:
    if sys.platform == "win32":
        candidate = ROOT / ".venv" / "Scripts" / "python.exe"
    else:
        candidate = ROOT / ".venv" / "bin" / "python"
    if candidate.is_file():
        return candidate
    return Path(sys.executable)


def _find_gdlint() -> Path:
    search_dirs: list[Path] = []
    scripts_dir = subprocess.check_output(
        [_project_python(), "-c", "import sysconfig; print(sysconfig.get_path('scripts'))"],
        text=True,
    ).strip()
    search_dirs.append(Path(scripts_dir))
    venv_scripts = _venv_scripts_dir()
    if venv_scripts is not None:
        search_dirs.append(venv_scripts)
    for directory in search_dirs:
        for name in ("gdlint.exe", "gdlint"):
            candidate = directory / name
            if candidate.exists():
                return candidate
    raise FileNotFoundError(
        "gdlint not found. Install with: make setup-dev"
    )


def run_lint() -> tuple[int, str]:
    output_lines: list[str] = []
    gdlint = _find_gdlint()
    output_lines.append("Running GDScript lint...")
    lint_proc = subprocess.run(
        [str(gdlint), *LINT_PATHS],
        cwd=str(ROOT),
        capture_output=True,
        text=True,
    )
    output_lines.append(lint_proc.stdout)
    output_lines.append(lint_proc.stderr)
    if lint_proc.returncode != 0:
        return lint_proc.returncode, "\n".join(line for line in output_lines if line)
    return 0, "\n".join(line for line in output_lines if line)


def _reaches_override_write(bodies: dict[str, str], body: str, depth: int) -> bool:
    if any(marker in body for marker in UI_OVERRIDE_WRITE_MARKERS):
        return True
    if depth <= 0:
        return False
    callees = set(re.findall(r"\b(_[a-z][a-z0-9_]*)\s*\(", body))
    return any(
        _reaches_override_write(bodies, bodies[callee], depth - 1)
        for callee in callees
        if callee in bodies
    )


def _function_bodies(source: str) -> dict[str, str]:
    bodies: dict[str, str] = {}
    current: str | None = None
    for line in source.splitlines():
        if line.strip().startswith("#"):
            continue
        header = re.match(r"(?:static )?func ([A-Za-z_][A-Za-z0-9_]*)\s*\(", line)
        if header is not None:
            current = header.group(1)
            bodies[current] = ""
            continue
        if current is None:
            continue
        if line and not line[0].isspace():
            current = None
            continue
        bodies[current] += line + "\n"
    return bodies


def run_ui_repaint_guard() -> tuple[int, str]:
    """Fail fast on UI scripts that repaint theme overrides from a theme-changed notify.

    Writing an override re-emits NOTIFICATION_THEME_CHANGED, so such a handler recurses
    until GDScript aborts it at 1024 frames. Every abort prints a full backtrace, which
    makes the Godot suite crawl instead of failing, so this has to block before Godot
    starts rather than being caught at runtime.
    """
    output_lines = ["Checking UI repaint-loop hazards..."]
    hazards: list[str] = []
    for path in sorted((ROOT / "scripts" / "ui").rglob("*.gd")):
        bodies = _function_bodies(path.read_text(encoding="utf-8"))
        handler = bodies.get("_notification", "")
        if "NOTIFICATION_THEME_CHANGED" not in handler:
            continue
        if _reaches_override_write(bodies, handler, 3):
            hazards.append(str(path.relative_to(ROOT)).replace("\\", "/"))
    if not hazards:
        output_lines.append("Success: no UI repaint-loop hazards.")
        return 0, "\n".join(output_lines)
    for hazard in hazards:
        output_lines.append(
            f"  {hazard}: repaints theme overrides from NOTIFICATION_THEME_CHANGED. "
            "The override re-emits that notification, so this recurses until the stack "
            "blows. Repaint from _ready and from export setters instead."
        )
    return 1, "\n".join(output_lines)


def run_gdscript_warnings(*, require_godot: bool = False) -> tuple[int, str]:
    """Fail on Godot GDScript analyzer WARNINGs for owned project paths."""
    output_lines: list[str] = ["Checking GDScript analyzer warnings..."]
    if find_godot_binary() is None:
        message = (
            "Godot executable not found; skipping GDScript warning probe. "
            "Set GODOT_PATH or run make setup-godot to enable this check."
        )
        output_lines.append(message)
        if require_godot:
            return 1, "\n".join(output_lines)
        return 0, "\n".join(output_lines)

    code, output, findings = run_warning_probe()
    if findings:
        output_lines.append(f"Found {len(findings)} GDScript warning(s):")
        output_lines.extend(f"  {item}" for item in findings)
        output_lines.append(
            "Fix these before committing. Re-run: python tools/run_checks.py --lint-only"
        )
        return 1, "\n".join(output_lines)
    if code != 0:
        output_lines.append(output)
        output_lines.append("GDScript warning probe failed.")
        return 1, "\n".join(output_lines)
    output_lines.append("Success: no GDScript analyzer warnings.")
    return 0, "\n".join(output_lines)


def _kill_process_tree(pid: int) -> None:
    if sys.platform == "win32":
        subprocess.run(
            ["taskkill", "/F", "/T", "/PID", str(pid)],
            capture_output=True,
            check=False,
        )
        return
    try:
        os.kill(pid, 15)
    except OSError:
        pass


def _godot_editor_running() -> bool:
    godot = find_godot_binary()
    names: set[str] = {"godot", "godot.exe"}
    if godot is not None:
        names.add(godot.name.lower())
        names.add(godot.stem.lower())
    try:
        if sys.platform == "win32":
            proc = subprocess.run(
                ["tasklist"],
                capture_output=True,
                text=True,
                check=False,
            )
            haystack = proc.stdout.lower()
            return any(name in haystack for name in names if name)
        proc = subprocess.run(
            ["pgrep", "-if", "godot"],
            capture_output=True,
            check=False,
        )
        return proc.returncode == 0
    except OSError:
        return False


def run_tests() -> tuple[int, str]:
    output_lines: list[str] = []

    _ensure_extensions_synced()

    if _godot_editor_running():
        message = (
            "Skipping Godot unit tests while the Godot editor is open "
            "(avoids GDExtension/autoload conflicts). Close Godot and run "
            "make check to execute the full suite."
        )
        output_lines.append(message)
        return 0, "\n".join(output_lines)

    manifest_issue = _validate_gdvosk_manifest()
    if manifest_issue is not None:
        output_lines.append(manifest_issue)
        return 1, "\n".join(output_lines)

    godot = find_godot_binary()
    if godot is None:
        message = (
            "Godot executable not found. Set GODOT_PATH, GODOT_EDITOR_WIN in "
            "tools/versions.env, godotTools.editorPath in .vscode/settings.json, "
            "or run: make setup-godot"
        )
        output_lines.append(message)
        return 1, "\n".join(output_lines)

    output_lines.append("Running Godot unit tests...")
    timeout_sec = int(os.environ.get("GODOT_TEST_TIMEOUT_SEC", "120"))
    env = os.environ.copy()
    env["FRIEND_SLOP_TEST"] = "1"
    env["STEAM_PROXIMITY_VOICE_TEST"] = "1"
    TEST_LOG.parent.mkdir(parents=True, exist_ok=True)
    stdout_text = ""
    try:
        with TEST_LOG.open("w", encoding="utf-8") as log_handle:
            test_proc = subprocess.run(
                [
                    str(godot),
                    "--headless",
                    "--path",
                    str(ROOT),
                    "--script",
                    "res://tests/run_tests.gd",
                ],
                cwd=str(ROOT),
                env=env,
                stdout=log_handle,
                stderr=subprocess.STDOUT,
                timeout=timeout_sec,
            )
        stdout_text = TEST_LOG.read_text(encoding="utf-8")
    except subprocess.TimeoutExpired as exc:
        proc = getattr(exc, "process", None)
        if proc is not None and proc.pid:
            _kill_process_tree(proc.pid)
        if TEST_LOG.exists():
            stdout_text = TEST_LOG.read_text(encoding="utf-8")
        output_lines.append(
            f"Godot unit tests timed out after {timeout_sec}s. "
            + "Set GODOT_TEST_TIMEOUT_SEC to override."
        )
        if stdout_text:
            output_lines.append(stdout_text)
        return 1, "\n".join(line for line in output_lines if line)
    output_lines.append(stdout_text)
    analyzer_issues = _find_gdscript_analyzer_issues(stdout_text)
    if analyzer_issues:
        output_lines.append("GDScript analyzer issues (see Godot output above):")
        output_lines.extend(analyzer_issues)
        return 1, "\n".join(line for line in output_lines if line)
    exit_code = _normalize_test_exit(test_proc.returncode, stdout_text, "")
    return exit_code, "\n".join(line for line in output_lines if line)


def run_checks(
    *,
    lint: bool = True,
    warnings: bool = True,
    tests: bool = True,
    require_godot_warnings: bool = False,
) -> tuple[int, str]:
    output_lines: list[str] = []

    if lint:
        lint_code, lint_output = run_lint()
        output_lines.append(lint_output)
        if lint_code != 0:
            return lint_code, "\n".join(line for line in output_lines if line)

        guard_code, guard_output = run_ui_repaint_guard()
        output_lines.append(guard_output)
        if guard_code != 0:
            return guard_code, "\n".join(line for line in output_lines if line)

    if warnings:
        warn_code, warn_output = run_gdscript_warnings(
            require_godot=require_godot_warnings
        )
        output_lines.append(warn_output)
        if warn_code != 0:
            return warn_code, "\n".join(line for line in output_lines if line)

    if tests:
        test_code, test_output = run_tests()
        output_lines.append(test_output)
        if test_code != 0:
            return test_code, "\n".join(line for line in output_lines if line)

    return 0, "\n".join(line for line in output_lines if line)


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run gdlint, GDScript warnings, and Godot unit tests."
    )
    group = parser.add_mutually_exclusive_group()
    group.add_argument(
        "--lint-only",
        action="store_true",
        help="Run gdlint + GDScript analyzer warnings (no unit tests).",
    )
    group.add_argument(
        "--tests-only",
        action="store_true",
        help="Run Godot unit tests only.",
    )
    group.add_argument(
        "--warnings-only",
        action="store_true",
        help="Run GDScript analyzer warning probe only (requires Godot).",
    )
    parser.add_argument(
        "--skip-warnings",
        action="store_true",
        help="Skip the GDScript analyzer warning probe.",
    )
    parser.add_argument(
        "--require-godot-warnings",
        action="store_true",
        help="Fail if Godot is missing when running the warning probe.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    _ensure_extensions_synced()
    args = _parse_args(argv or sys.argv[1:])
    if args.warnings_only:
        lint, warnings, tests = False, True, False
        require_godot = True
    else:
        lint = not args.tests_only
        tests = not args.lint_only
        warnings = not args.skip_warnings and not args.tests_only
        require_godot = args.require_godot_warnings
    code, output = run_checks(
        lint=lint,
        warnings=warnings,
        tests=tests,
        require_godot_warnings=require_godot,
    )
    if code != 0:
        print(output, file=sys.stderr)
        return code
    if output:
        print(output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
