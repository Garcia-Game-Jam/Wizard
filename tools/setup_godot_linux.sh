#!/usr/bin/env bash
# Downloads the pinned Linux Godot editor binary into .cache/godot/ (for CI + local smoke).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tools/load_versions.sh
source "$ROOT/tools/load_versions.sh"
# shellcheck source=tools/ci_log.sh
source "$ROOT/tools/ci_log.sh"
load_versions "$ROOT/tools/versions.env"

ci_step_start "setup_godot_linux"

CACHE_DIR="$ROOT/.cache/godot"
ZIP_NAME="Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
URL="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable/${ZIP_NAME}"
BIN_NAME="Godot_v${GODOT_VERSION}-stable_linux.x86_64"
BIN_PATH="$CACHE_DIR/$BIN_NAME"
ZIP_PATH="$CACHE_DIR/$ZIP_NAME"

mkdir -p "$CACHE_DIR"

if [[ -x "$BIN_PATH" ]]; then
	ci_log "Using cached Godot binary: $BIN_PATH"
	ci_step_end "setup_godot_linux"
	exit 0
fi

download() {
	local dest="$1"
	local url="$2"
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL -o "$dest" "$url"
	elif command -v wget >/dev/null 2>&1; then
		wget -q -O "$dest" "$url"
	else
		ci_log "ERROR: need curl or wget to download Godot"
		exit 1
	fi
}

if [[ ! -f "$ZIP_PATH" ]]; then
	ci_log "Downloading Godot ${GODOT_VERSION} from $URL"
	download "$ZIP_PATH" "$URL"
	ci_log "Download complete: $(du -h "$ZIP_PATH" | awk '{print $1}')"
else
	ci_log "Using cached zip: $ZIP_PATH"
fi

if ! command -v unzip >/dev/null 2>&1; then
	ci_log "ERROR: unzip is required to extract Godot"
	exit 1
fi

TEMP_EXTRACT="$(mktemp -d)"
trap 'rm -rf "$TEMP_EXTRACT"' EXIT
ci_log "Extracting $ZIP_NAME ..."
unzip -q "$ZIP_PATH" -d "$TEMP_EXTRACT"
EXTRACTED="$(find "$TEMP_EXTRACT" -maxdepth 1 -type f -name "$BIN_NAME" | head -n 1)"
if [[ -z "$EXTRACTED" || ! -f "$EXTRACTED" ]]; then
	ci_log "ERROR: $BIN_NAME not found inside $ZIP_PATH"
	exit 1
fi

mv "$EXTRACTED" "$BIN_PATH"
chmod +x "$BIN_PATH"
ci_log "Installed Godot to $BIN_PATH"
ci_step_end "setup_godot_linux"
