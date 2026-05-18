#!/usr/bin/env bash
# build.sh — share-forge PyInstaller build
set -e

PROJECT="share-forge"
DIST_DIR="dist"
BIN_DIR="bin"

echo "================================================"
echo "  $PROJECT — Build Script"
echo "================================================"

# ── venv ──────────────────────────────────────────
if [ ! -d ".venv" ]; then
    echo "[*] Creating .venv..."
    python3 -m venv .venv
fi

source .venv/bin/activate
pip install --upgrade pip -q
pip install -r requirements.txt pyinstaller -q
echo "[*] Dependencies installed."

# ── GUI binary ────────────────────────────────────
echo "[*] Building GUI binary..."
pyinstaller \
    --onefile \
    --name "${PROJECT}" \
    --windowed \
    --add-data "core:core" \
    --add-data "gui:gui" \
    --hidden-import PyQt6.QtWidgets \
    --hidden-import PyQt6.QtCore \
    --hidden-import PyQt6.QtGui \
    --hidden-import flask \
    --hidden-import werkzeug \
    main.py

# ── CLI binary ────────────────────────────────────
echo "[*] Building CLI binary..."
pyinstaller \
    --onefile \
    --name "${PROJECT}-cli" \
    --add-data "core:core" \
    --hidden-import flask \
    --hidden-import werkzeug \
    cli/main.py

# ── Move binaries to bin/ ─────────────────────────
echo "[*] Moving binaries to ${BIN_DIR}/..."
mkdir -p "${BIN_DIR}"
rm -f "${BIN_DIR}/${PROJECT}" "${BIN_DIR}/${PROJECT}-cli"
mv "${DIST_DIR}/${PROJECT}"     "${BIN_DIR}/${PROJECT}"
mv "${DIST_DIR}/${PROJECT}-cli" "${BIN_DIR}/${PROJECT}-cli"

# ── Cleanup ───────────────────────────────────────
echo "[*] Cleaning up build artifacts..."
rm -rf build dist
rm -f "${PROJECT}.spec" "${PROJECT}-cli.spec"

echo "================================================"
echo "  Build complete:"
ls -lh "${BIN_DIR}/${PROJECT}" "${BIN_DIR}/${PROJECT}-cli"
echo "================================================"
