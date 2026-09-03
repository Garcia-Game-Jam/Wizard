SHELL := /bin/bash
.PHONY: help setup-dev setup-voice setup-blender lint warnings test test-e2e-lan check verify-pinned-versions verify-voice verify-blender

ifeq ($(OS),Windows_NT)
PYTHON ?= python
VENV_PY := .venv/Scripts/python.exe
else
PYTHON ?= python3
VENV_PY := .venv/bin/python
endif

ifneq ($(wildcard $(VENV_PY)),)
RUN_PYTHON := $(VENV_PY)
else
RUN_PYTHON := $(PYTHON)
endif

include tools/versions.mk

ifeq ($(OS),Windows_NT)
GODOT ?= $(GODOT_EDITOR_WIN)
else
GODOT ?= godot
endif

help:
	@echo "Wizard dev targets (Godot $(GODOT_VERSION), GodotSteam $(GODOTSTEAM_VERSION))"
	@echo ""
	@echo "  make setup-dev             pip install -r requirements-dev.txt (uses .venv)"
	@echo "  make setup-voice           gdvosk + Vosk model (~500 MB first run)"
	@echo "  make setup-blender         Blender MCP for Cursor (uv + addon + mcp.json)"
	@echo "  make lint                  gdlint + GDScript analyzer warnings"
	@echo "  make warnings              GDScript analyzer warning probe (requires Godot)"
	@echo "  make test                  Godot unit tests"
	@echo "  make test-e2e-lan          Optional two-process LAN pit (not in make test)"
	@echo "  make check                 lint + test"
	@echo "  make verify-pinned-versions  CI guard: workflows match tools/versions.env"
	@echo "  make verify-voice          quick file check for gdvosk install"
	@echo "  make verify-blender        uv + .cursor/mcp.json blender entry"
	@echo ""
	@echo "Override Godot binary: make test GODOT=/path/to/godot"
	@echo "Windows default Godot: tools/versions.env GODOT_EDITOR_WIN"
	@echo "Pinned versions live in tools/versions.env"

setup-dev:
	@$(PYTHON) -m venv .venv || ( \
		echo "error: could not create .venv (on Ubuntu: sudo apt install python3-venv)" >&2; \
		exit 1 \
	)
	$(VENV_PY) -m pip install --disable-pip-version-check -U pip
	$(VENV_PY) -m pip install --disable-pip-version-check -r requirements-dev.txt

setup-voice:
ifeq ($(OS),Windows_NT)
	powershell -ExecutionPolicy Bypass -File tools/setup_gdvosk.ps1
else
	bash tools/setup_gdvosk.sh
endif

setup-blender:
	$(RUN_PYTHON) tools/setup_blender_mcp.py

lint:
	$(RUN_PYTHON) tools/run_checks.py --lint-only

warnings:
	$(RUN_PYTHON) tools/run_checks.py --warnings-only --require-godot-warnings

test:
	GODOT_PATH="$(GODOT)" $(RUN_PYTHON) tools/run_checks.py --tests-only

test-e2e-lan:
	GODOT_PATH="$(GODOT)" $(RUN_PYTHON) tools/run_e2e_lan.py

check: lint test

verify-pinned-versions:
	$(PYTHON) tools/check_pinned_versions.py

verify-voice:
ifeq ($(OS),Windows_NT)
	powershell -ExecutionPolicy Bypass -File tools/verify_gdvosk.ps1
else
	@test -f addons/gdvosk/gdvosk.gdextension || \
		(echo "gdvosk missing. Run: make setup-voice" >&2; exit 1)
	@test -d models/vosk/am || \
		(echo "Vosk model missing. Run: make setup-voice" >&2; exit 1)
	@echo "Voice dependencies OK ($(GDVOSK_ZIP), $(VOSK_MODEL_ZIP))"
endif

verify-blender:
	$(RUN_PYTHON) tools/setup_blender_mcp.py --verify
