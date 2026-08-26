#!/usr/bin/env bash
# Godot headless import — used by CI test job and local smoke scripts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tools/load_versions.sh
source "$ROOT/tools/load_versions.sh"
# shellcheck source=tools/ci_log.sh
source "$ROOT/tools/ci_log.sh"
load_versions "$ROOT/tools/versions.env"

BIN_NAME="Godot_v${GODOT_VERSION}-stable_linux.x86_64"
GODOT_BIN="${GODOT_BIN:-$ROOT/.cache/godot/$BIN_NAME}"
IMPORT_TIMEOUT_SEC="${GODOT_IMPORT_TIMEOUT_SEC:-180}"
LOG_DIR="$ROOT/.cache/ci-logs"
LOG_FILE="$LOG_DIR/godot-import.log"

if [[ ! -x "$GODOT_BIN" ]]; then
	ci_log "ERROR: Godot not found at $GODOT_BIN (run tools/setup_godot_linux.sh)"
	exit 1
fi

mkdir -p "$LOG_DIR"
cd "$ROOT"

GDEXT="$ROOT/addons/gdvosk/gdvosk.gdextension"
GDEXT_DISABLED="$ROOT/addons/gdvosk/gdvosk.gdextension.disabled"

ensure_extensions_restored() {
	if [[ -f "$GDEXT_DISABLED" && ! -f "$GDEXT" ]]; then
		mv "$GDEXT_DISABLED" "$GDEXT"
		ci_log "Restored gdvosk.gdextension left disabled by an older test run"
	fi
}

ensure_extensions_restored

ci_step_start "godot_import"
ci_log "Godot binary: $GODOT_BIN"
ci_log "Import timeout: ${IMPORT_TIMEOUT_SEC}s"
ci_log "Import log: $LOG_FILE"

if [[ -d "$ROOT/.godot" ]]; then
	ci_log ".godot cache present ($(du -sh "$ROOT/.godot" 2>/dev/null | awk '{print $1}' || echo 'unknown size'))"
else
	ci_log ".godot cache missing — full import expected"
fi

godot_args=(--headless --path . --import)
if [[ "${GODOT_CI_VERBOSE:-}" == "1" ]]; then
	godot_args=(--verbose "${godot_args[@]}")
fi

_import_start=$SECONDS
(
	while true; do
		sleep 15
		ci_log "import still running ($((SECONDS - _import_start))s wall) ..."
	done
) &
HEARTBEAT_PID=$!

set +e
if command -v timeout >/dev/null 2>&1; then
	timeout "$IMPORT_TIMEOUT_SEC" "$GODOT_BIN" "${godot_args[@]}" >"$LOG_FILE" 2>&1
	exit_code=$?
else
	"$GODOT_BIN" "${godot_args[@]}" >"$LOG_FILE" 2>&1
	exit_code=$?
fi
set -e

kill "$HEARTBEAT_PID" 2>/dev/null || true
wait "$HEARTBEAT_PID" 2>/dev/null || true

if [[ "$exit_code" -eq 124 ]]; then
	ci_log "ERROR: Godot import timed out after ${IMPORT_TIMEOUT_SEC}s"
	ci_log "Last 60 lines of import log:"
	tail -60 "$LOG_FILE" | sed 's/^/[godot] /'
	ci_step_end "godot_import"
	exit 1
fi

if [[ "$exit_code" -ne 0 ]]; then
	if [[ "$exit_code" -eq 139 ]] && grep -q '\[ DONE \].*first_scan_filesystem' "$LOG_FILE" 2>/dev/null; then
		ci_log "WARN: Godot import exited with segfault (139) after completing import; treating as success"
		ci_log "Import finished OK (gdvosk unload crash on exit)"
		ci_step_end "godot_import"
		exit 0
	fi
	ci_log "ERROR: Godot import failed (exit $exit_code)"
	tail -60 "$LOG_FILE" | sed 's/^/[godot] /'
	ci_step_end "godot_import"
	exit "$exit_code"
fi

ci_log "Import finished OK"
ci_step_end "godot_import"
