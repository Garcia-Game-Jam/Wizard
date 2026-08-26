#!/usr/bin/env bash
# Installs gdvosk GDExtension and a small English Vosk model for Wizard.
# Run from repo root: bash tools/setup_gdvosk.sh
#
# Downloads ~500 MB on first run; later runs use .cache/voice-setup/ and skip
# re-download when addons/ and models/ are already present.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tools/load_versions.sh
source "$ROOT/tools/load_versions.sh"
load_versions "$ROOT/tools/versions.env"

CACHE="$ROOT/.cache/voice-setup"
ADDONS_DIR="$ROOT/addons/gdvosk"
MODEL_DIR="$ROOT/models/vosk"

GDVOSK_URL="https://github.com/Nihlus/gdvosk/releases/download/${GDVOSK_RELEASE_TAG}/${GDVOSK_ZIP}"
MODEL_URL="https://alphacephei.com/vosk/models/${VOSK_MODEL_ZIP}"

mkdir -p "$CACHE" "$(dirname "$ADDONS_DIR")" "$(dirname "$MODEL_DIR")"

download_if_missing() {
	local url="$1"
	local dest="$2"
	if [[ -f "$dest" ]]; then
		echo "Using cached $(basename "$dest")"
		return
	fi
	echo "Downloading $url ..."
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL -o "$dest" "$url"
	elif command -v wget >/dev/null 2>&1; then
		wget -q -O "$dest" "$url"
	else
		echo "error: need curl or wget to download voice dependencies." >&2
		exit 1
	fi
}

require_unzip() {
	if command -v unzip >/dev/null 2>&1; then
		return
	fi
	echo "error: unzip is required to extract voice dependencies." >&2
	exit 1
}

find_gdvosk_root() {
	local search_root="$1"
	local candidates=(
		"$search_root/addons/gdvosk"
		"$search_root/gdvosk"
		"$search_root"
	)
	local candidate
	for candidate in "${candidates[@]}"; do
		if [[ -f "$candidate/gdvosk.gdextension" ]]; then
			echo "$candidate"
			return 0
		fi
	done
	return 1
}

ensure_gdvosk_editor_libraries() {
	local gdextension="$ADDONS_DIR/gdvosk.gdextension"
	if [[ ! -f "$gdextension" ]]; then
		return
	fi
	if grep -q 'windows\.editor\.x86_64' "$gdextension"; then
		echo "gdvosk.gdextension already has editor library entries"
		return
	fi
	echo "Patching gdvosk.gdextension for Godot editor (windows.editor / linux.editor / macos.editor) ..."
	local tmp="${gdextension}.tmp"
	sed \
		-e 's|\(macos\.debug = "res://addons/gdvosk/lib/macos/universal/libgdvosk-d\.dylib"\)|\1\
macos.editor = "res://addons/gdvosk/lib/macos/universal/libgdvosk-d.dylib"|' \
		-e 's|\(windows\.debug\.x86_32 = "res://addons/gdvosk/lib/windows/x86_32/libgdvosk-d\.dll"\)|\1\
windows.editor.x86_32 = "res://addons/gdvosk/lib/windows/x86_32/libgdvosk-d.dll"|' \
		-e 's|\(windows\.debug\.x86_64 = "res://addons/gdvosk/lib/windows/x86_64/libgdvosk-d\.dll"\)|\1\
windows.editor.x86_64 = "res://addons/gdvosk/lib/windows/x86_64/libgdvosk-d.dll"|' \
		-e 's|\(linux\.debug\.x86_64 = "res://addons/gdvosk/lib/linux/x86_64/libgdvosk-d\.so"\)|\1\
linux.editor.x86_64 = "res://addons/gdvosk/lib/linux/x86_64/libgdvosk-d.so"|' \
		"$gdextension" >"$tmp"
	mv "$tmp" "$gdextension"
}

GDVOSK_ZIP_PATH="$CACHE/$GDVOSK_ZIP"
MODEL_ZIP_PATH="$CACHE/$VOSK_MODEL_ZIP"

NEED_EXTRACT=false
if [[ ! -f "$ADDONS_DIR/gdvosk.gdextension" ]]; then
	NEED_EXTRACT=true
fi
if [[ ! -d "$MODEL_DIR/am" ]]; then
	NEED_EXTRACT=true
fi

if [[ "$NEED_EXTRACT" == "true" ]]; then
	require_unzip
fi

download_if_missing "$GDVOSK_URL" "$GDVOSK_ZIP_PATH"
download_if_missing "$MODEL_URL" "$MODEL_ZIP_PATH"

if [[ ! -f "$ADDONS_DIR/gdvosk.gdextension" ]]; then
	echo "Extracting gdvosk to addons/ ..."
	TEMP_EXTRACT="$(mktemp -d)"
	trap 'rm -rf "$TEMP_EXTRACT"' EXIT
	unzip -q "$GDVOSK_ZIP_PATH" -d "$TEMP_EXTRACT"
	SOURCE="$(find_gdvosk_root "$TEMP_EXTRACT")"
	rm -rf "$ADDONS_DIR"
	cp -R "$SOURCE" "$ADDONS_DIR"
	echo "gdvosk installed to $ADDONS_DIR"
else
	echo "gdvosk already installed at $ADDONS_DIR"
fi

if [[ ! -f "$ADDONS_DIR/lib/linux/x86_64/libgdvosk-d.so" ]]; then
	echo "error: gdvosk Linux libraries missing under $ADDONS_DIR/lib/linux/x86_64/" >&2
	exit 1
fi

if [[ ! -f "$ADDONS_DIR/lib/windows/x86_64/libgdvosk-d.dll" ]]; then
	echo "error: gdvosk Windows libraries missing under $ADDONS_DIR/lib/windows/x86_64/" >&2
	exit 1
fi

ensure_gdvosk_editor_libraries

if [[ ! -d "$MODEL_DIR/am" ]]; then
	echo "Extracting Vosk model to models/vosk/ ..."
	TEMP_MODEL="$(mktemp -d)"
	trap 'rm -rf "$TEMP_MODEL"' EXIT
	unzip -q "$MODEL_ZIP_PATH" -d "$TEMP_MODEL"
	INNER="$(find "$TEMP_MODEL" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
	if [[ -z "$INNER" ]]; then
		echo "error: Vosk model zip was empty." >&2
		exit 1
	fi
	rm -rf "$MODEL_DIR"
	cp -R "$INNER" "$MODEL_DIR"
	echo "Vosk model installed to $MODEL_DIR"
else
	echo "Vosk model already installed at $MODEL_DIR"
fi

echo ""
echo "Done. Fully quit Godot (all windows), reopen the project, then test speech in-game."
