#!/usr/bin/env bash
# Headless unit tests — same entry point as the GitHub Actions test job.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tools/load_versions.sh
source "$ROOT/tools/load_versions.sh"
# shellcheck source=tools/ci_log.sh
source "$ROOT/tools/ci_log.sh"
load_versions "$ROOT/tools/versions.env"

BIN_NAME="Godot_v${GODOT_VERSION}-stable_linux.x86_64"
GODOT_BIN="${GODOT_BIN:-$ROOT/.cache/godot/$BIN_NAME}"
TIMEOUT_SEC="${GODOT_TEST_TIMEOUT_SEC:-120}"
LOG_DIR="$ROOT/.cache/ci-logs"
LOG_FILE="$LOG_DIR/godot-tests.log"

if [[ ! -x "$GODOT_BIN" ]]; then
	ci_log "ERROR: Godot not found at $GODOT_BIN (run tools/setup_godot_linux.sh)"
	exit 1
fi

GDEXT="$ROOT/addons/gdvosk/gdvosk.gdextension"
GDEXT_DISABLED="$ROOT/addons/gdvosk/gdvosk.gdextension.disabled"
ensure_extensions_restored() {
	if [[ -f "$GDEXT_DISABLED" && ! -f "$GDEXT" ]]; then
		mv "$GDEXT_DISABLED" "$GDEXT"
	fi
}

ci_step_start "godot_unit_tests"
ensure_extensions_restored
ci_log "Godot binary: $GODOT_BIN"
ci_log "Test timeout: ${TIMEOUT_SEC}s"
ci_log "Test log: $LOG_FILE"

mkdir -p "$LOG_DIR"
cd "$ROOT"

export FRIEND_SLOP_TEST=1

godot_args=(--headless --path . --script res://tests/run_tests.gd)
if [[ "${GODOT_CI_VERBOSE:-}" == "1" ]]; then
	godot_args=(--verbose "${godot_args[@]}")
fi

_test_start=$SECONDS
(
	while true; do
		sleep 10
		ci_log "tests still running ($((SECONDS - _test_start))s wall) ..."
		if [[ -f "$LOG_FILE" ]]; then
			last_line="$(tail -1 "$LOG_FILE" 2>/dev/null || true)"
			if [[ -n "$last_line" ]]; then
				ci_log "last godot output: $last_line"
			fi
		fi
	done
) &
HEARTBEAT_PID=$!

set +e
if command -v timeout >/dev/null 2>&1; then
	timeout "$TIMEOUT_SEC" "$GODOT_BIN" "${godot_args[@]}" >"$LOG_FILE" 2>&1
	exit_code=$?
else
	"$GODOT_BIN" "${godot_args[@]}" >"$LOG_FILE" 2>&1
	exit_code=$?
fi
set -e

kill "$HEARTBEAT_PID" 2>/dev/null || true
wait "$HEARTBEAT_PID" 2>/dev/null || true

# Always print test output to CI console (helps post-mortem even on success).
if [[ -f "$LOG_FILE" ]]; then
	ci_log "Godot test output:"
	cat "$LOG_FILE" | sed 's/^/[godot] /'
fi

if [[ "$exit_code" -eq 124 ]]; then
	ci_log "ERROR: Godot unit tests timed out after ${TIMEOUT_SEC}s"
	ci_log "Process was killed — check heartbeat lines above for last activity"
	ci_step_end "godot_unit_tests"
	exit 1
fi

if [[ "$exit_code" -ne 0 ]]; then
	if grep -q "All tests passed." "$LOG_FILE" 2>/dev/null && [[ "$exit_code" -eq 139 ]]; then
		ci_log "WARN: Godot tests exited with segfault (139) after passing; treating as success (gdvosk unload crash)"
		exit_code=0
	fi
fi

if [[ "$exit_code" -ne 0 ]]; then
	ci_log "ERROR: Godot unit tests failed (exit $exit_code)"
	ci_step_end "godot_unit_tests"
	exit "$exit_code"
fi

ci_log "All tests passed"
ci_step_end "godot_unit_tests"
