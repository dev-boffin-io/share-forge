# Makefile — share-forge

PROJECT     := share-forge
PREFIX      ?= $(HOME)/.local
BINDIR      := $(PREFIX)/bin
APPDIR      := $(HOME)/.local/share/applications
ICONDIR     := $(HOME)/.local/share/icons/hicolor/256x256/apps
ICON_THEME  := $(HOME)/.local/share/icons/hicolor

BIN_DIR     := bin
DIST_DIR    := dist
VENV        := .venv

GUI_BIN     := $(BIN_DIR)/$(PROJECT)
CLI_BIN     := $(BIN_DIR)/$(PROJECT)-cli

ifdef DEBUG
	PYINST_FLAGS := --log-level DEBUG
else
	PYINST_FLAGS :=
endif

.PHONY: all help deps build install uninstall clean

all: help

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

deps:
	@echo "[*] Checking system deps..."
	@python3 -c "import ensurepip" 2>/dev/null || sudo apt-get install -y python3-venv python3-pip -q
	@if [ ! -f "$(VENV)/bin/pip" ]; then \
		echo "[*] Creating virtualenv..."; \
		rm -rf $(VENV); \
		python3 -m venv --clear $(VENV); \
	fi
	@echo "[*] Installing Python deps..."
	@$(VENV)/bin/pip install --upgrade pip -q
	@$(VENV)/bin/pip install -r requirements.txt pyinstaller -q

build: deps
	@echo "[*] Building GUI binary..."
	$(VENV)/bin/pyinstaller $(PYINST_FLAGS) \
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
	$(VENV)/bin/pyinstaller $(PYINST_FLAGS) \
		--onefile \
		--name "$(PROJECT)-cli" \
		--add-data "core:core" \
		--hidden-import flask \
		--hidden-import werkzeug \
		cli/main.py
	@mkdir -p $(BIN_DIR)
	@rm -f $(GUI_BIN) $(CLI_BIN)
	@mv $(DIST_DIR)/$(PROJECT)     $(GUI_BIN)
	@mv $(DIST_DIR)/$(PROJECT)-cli $(CLI_BIN)
	@chmod +x $(GUI_BIN) $(CLI_BIN)
	@rm -rf build dist *.spec
	@echo ""
	@echo "[✓] Build complete:"
	@ls -lh $(GUI_BIN) $(CLI_BIN)
	@echo ""

install:
	@test -f $(GUI_BIN) || { echo "[!] Run 'make build' first."; exit 1; }
	@echo "[*] Installing binaries to $(BINDIR)..."
	@mkdir -p $(BINDIR)
	@cp $(GUI_BIN)  $(BINDIR)/$(PROJECT)
	@cp $(CLI_BIN)  $(BINDIR)/$(PROJECT)-cli
	@chmod +x $(BINDIR)/$(PROJECT) $(BINDIR)/$(PROJECT)-cli
	@echo "[*] Installing icon..."
	@mkdir -p $(ICONDIR)
	@cp assets/$(PROJECT).png $(ICONDIR)/$(PROJECT).png
	@if command -v gtk-update-icon-cache >/dev/null 2>&1; then \
		gtk-update-icon-cache -f -t $(ICON_THEME) 2>/dev/null || true; \
		echo "[~] Icon cache updated (or skipped)."; \
	elif command -v gtk4-update-icon-cache >/dev/null 2>&1; then \
		gtk4-update-icon-cache -f -t $(ICON_THEME) 2>/dev/null || true; \
		echo "[~] Icon cache updated (gtk4, or skipped)."; \
	else \
		echo "[~] gtk-update-icon-cache not found — icon may not appear immediately."; \
	fi
	@echo "[*] Installing .desktop entry..."
	@mkdir -p $(APPDIR)
	@printf '[Desktop Entry]\nVersion=1.0\nType=Application\nName=Share Forge\nGenericName=LAN File Server\nComment=Browse, upload, and download files over LAN\nExec=%s\nIcon=%s\nTerminal=false\nCategories=Network;FileTransfer;\nKeywords=share;file;lan;server;network;\nStartupNotify=true\n' \
		"$(BINDIR)/$(PROJECT)" "$(PROJECT)" \
		> $(APPDIR)/$(PROJECT).desktop
	@chmod +x $(APPDIR)/$(PROJECT).desktop
	@if command -v update-desktop-database >/dev/null 2>&1; then \
		update-desktop-database $(APPDIR) 2>/dev/null || true; \
	fi
	@echo ""
	@echo "[✓] Installed:"
	@echo "    Binary  →  $(BINDIR)/$(PROJECT)"
	@echo "    CLI     →  $(BINDIR)/$(PROJECT)-cli"
	@echo "    Icon    →  $(ICONDIR)/$(PROJECT).png"
	@echo "    Desktop →  $(APPDIR)/$(PROJECT).desktop"
	@echo ""

uninstall:
	@echo "[*] Removing installed files..."
	@rm -f $(BINDIR)/$(PROJECT) $(BINDIR)/$(PROJECT)-cli
	@rm -f $(APPDIR)/$(PROJECT).desktop
	@rm -f $(ICONDIR)/$(PROJECT).png
	@if command -v gtk-update-icon-cache >/dev/null 2>&1; then \
		gtk-update-icon-cache -f -t $(ICON_THEME) 2>/dev/null || true; \
	fi
	@if command -v update-desktop-database >/dev/null 2>&1; then \
		update-desktop-database $(APPDIR) 2>/dev/null || true; \
	fi
	@echo "[✓] Uninstalled."

clean:
	@echo "[*] Cleaning build artefacts..."
	@rm -rf build dist $(BIN_DIR) *.spec
	@find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	@echo "[✓] Clean."
