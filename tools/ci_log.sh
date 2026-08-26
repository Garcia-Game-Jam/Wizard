#!/usr/bin/env bash
# Timestamped logging helpers for CI and local smoke scripts.

ci_log() {
	printf '[ci %s] %s\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')" "$*"
}

ci_step_start() {
	CI_CURRENT_STEP="$1"
	CI_STEP_START_SEC=$SECONDS
	ci_log "START: $1"
}

ci_step_end() {
	local label="${1:-$CI_CURRENT_STEP}"
	local elapsed=$((SECONDS - CI_STEP_START_SEC))
	ci_log "DONE:  ${label} (${elapsed}s)"
}
