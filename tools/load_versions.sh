#!/usr/bin/env bash
# Sources tools/versions.env into the current shell. No-op for blank lines and comments.

load_versions() {
	local versions_file="$1"
	local line key value
	while IFS= read -r line || [[ -n "$line" ]]; do
		[[ "$line" =~ ^[[:space:]]*# ]] && continue
		[[ "$line" != *"="* ]] && continue
		key="${line%%=*}"
		value="${line#*=}"
		export "${key}=${value}"
	done <"$versions_file"
}
