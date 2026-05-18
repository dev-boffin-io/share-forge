# Makefile — share-forge
# Usage:
#   make build        Build GUI + CLI binaries  → ./bin/
#   make install      Install binary + .desktop entry
#   make uninstall    Remove installed files
#   make clean        Remove build artefacts
#   make help         Show this message
#
# Options:
#   DEBUG=1           Verbose PyInstaller output  (make build DEBUG=1)
#   PREFIX=<path>     Install prefix              (default: ~/.local)

PROJECT     := share-forge
PREFIX      ?= $(HOME)/.local
BINDIR      := $(PREFIX)/bin
APPDIR      := $(HOME)/.local/share/applications
ICONDIR     := $(HOME)/.local/share/icons/hicolor/256x256/apps

BIN_DIR     := bin
DIST_DIR    := dist
VENV        := .venv
PY          := $(VENV)/bin/python
PIP         := $(VENV)/bin/pip
PYINSTALLER := $(VENV)/bin/pyinstaller

GUI_BIN     := $(BIN_DIR)/$(PROJECT)
CLI_BIN     := $(BIN_DIR)/$(PROJECT)-cli

ifdef DEBUG
	PYINST_FLAGS := --log-level DEBUG
else
	PYINST_FLAGS :=
endif

# ── Default target ────────────────────────────────────────────────────────────
.PHONY: all
all: help

# ── Help ──────────────────────────────────────────────────────────────────────
.PHONY: help
help:
	@echo ""
	@echo "  share-forge — Build & Install"
	@echo ""
	@echo "  Targets:"
	@echo "    make build        Build GUI + CLI  →  ./bin/"
	@echo "    make install      Install binary + .desktop entry"
	@echo "    make uninstall    Remove installed files"
	@echo "    make clean        Remove build artefacts"
	@echo "    make help         Show this message"
	@echo ""
	@echo "  Options:"
	@echo "    DEBUG=1           Verbose PyInstaller output"
	@echo "    PREFIX=<path>     Install prefix  (default: ~/.local)"
	@echo ""

# ── venv + deps ───────────────────────────────────────────────────────────────
$(VENV)/bin/activate:
	@echo "[*] Creating virtualenv..."
	python3 -m venv $(VENV)
	$(PIP) install --upgrade pip -q
	$(PIP) install -r requirements.txt pyinstaller -q
	@echo "[*] Dependencies installed."

.PHONY: deps
deps: $(VENV)/bin/activate

# ── Build ─────────────────────────────────────────────────────────────────────
.PHONY: build
build: deps
	@echo "[*] Building GUI binary..."
	$(PYINSTALLER) $(PYINST_FLAGS) \
		--onefile \
		--name "$(PROJECT)" \
		--windowed \
		--add-data "core:core" \
		--add-data "gui:gui" \
		--hidden-import PyQt6.QtWidgets \
		--hidden-import PyQt6.QtCore \
		--hidden-import PyQt6.QtGui \
		--hidden-import flask \
		--hidden-import werkzeug \
		main.py
	@echo "[*] Building CLI binary..."
	$(PYINSTALLER) $(PYINST_FLAGS) \
		--onefile \
		--name "$(PROJECT)-cli" \
		--add-data "core:core" \
		--hidden-import flask \
		--hidden-import werkzeug \
		cli/main.py
	@mkdir -p $(BIN_DIR)
	@mv $(DIST_DIR)/$(PROJECT)     $(GUI_BIN)
	@mv $(DIST_DIR)/$(PROJECT)-cli $(CLI_BIN)
	@rm -rf build dist *.spec
	@echo ""
	@echo "[✓] Build complete:"
	@ls -lh $(GUI_BIN) $(CLI_BIN)
	@echo ""

# ── Install ───────────────────────────────────────────────────────────────────
.PHONY: install
install:
	@test -f $(GUI_BIN) || { echo "[!] Run 'make build' first."; exit 1; }
	@echo "[*] Installing binaries to $(BINDIR)..."
	@mkdir -p $(BINDIR)
	@cp $(GUI_BIN)  $(BINDIR)/$(PROJECT)
	@cp $(CLI_BIN)  $(BINDIR)/$(PROJECT)-cli
	@chmod +x $(BINDIR)/$(PROJECT) $(BINDIR)/$(PROJECT)-cli
	@echo "[*] Installing .desktop entry..."
	@mkdir -p $(APPDIR)
	@printf '[Desktop Entry]\nVersion=1.0\nType=Application\nName=Share Forge\nGenericName=LAN File Server\nComment=Browse, upload, and download files over LAN\nExec=%s\nIcon=%s\nTerminal=false\nCategories=Network;FileTransfer;\nKeywords=share;file;lan;server;network;\nStartupNotify=true\n' \
		"$(BINDIR)/$(PROJECT)" "$(PROJECT)" \
		> $(APPDIR)/$(PROJECT).desktop
	@if [ -f assets/$(PROJECT).png ]; then \
		echo "[*] Installing icon..."; \
		mkdir -p $(ICONDIR); \
		cp assets/$(PROJECT).png $(ICONDIR)/$(PROJECT).png; \
	else \
		echo "[~] No icon found at assets/$(PROJECT).png — skipping."; \
	fi
	@if command -v update-desktop-database >/dev/null 2>&1; then \
		update-desktop-database $(APPDIR); \
	fi
	@echo ""
	@echo "[✓] Installed:"
	@echo "    Binary  →  $(BINDIR)/$(PROJECT)"
	@echo "    CLI     →  $(BINDIR)/$(PROJECT)-cli"
	@echo "    Desktop →  $(APPDIR)/$(PROJECT).desktop"
	@echo ""

# ── Uninstall ─────────────────────────────────────────────────────────────────
.PHONY: uninstall
uninstall:
	@echo "[*] Removing installed files..."
	@rm -f $(BINDIR)/$(PROJECT)
	@rm -f $(BINDIR)/$(PROJECT)-cli
	@rm -f $(APPDIR)/$(PROJECT).desktop
	@rm -f $(ICONDIR)/$(PROJECT).png
	@if command -v update-desktop-database >/dev/null 2>&1; then \
		update-desktop-database $(APPDIR) 2>/dev/null || true; \
	fi
	@echo "[✓] Uninstalled."

# ── Clean ─────────────────────────────────────────────────────────────────────
.PHONY: clean
clean:
	@echo "[*] Cleaning build artefacts..."
	@rm -rf build dist $(BIN_DIR) *.spec
	@find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	@echo "[✓] Clean."
