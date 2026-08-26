SHELL := /bin/bash
.PHONY: help setup-dev setup-voice lint warnings verify-voice

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
	@echo "  make lint                  gdlint"
	@echo "  make warnings              GDScript analyzer warning probe (requires Godot)"
	@echo "  make verify-voice          quick file check for gdvosk install"
	@echo ""
	@echo "Override Godot binary: make warnings GODOT=/path/to/godot"
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

lint:
	$(RUN_PYTHON) tools/run_checks.py --lint-only

warnings:
	$(RUN_PYTHON) tools/run_checks.py --warnings-only --require-godot-warnings

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
