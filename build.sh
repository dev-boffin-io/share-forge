#!/usr/bin/env bash
# build.sh — share-forge Linux build script
set -euo pipefail

PROJECT="share-forge"
BIN_DIR="bin"
DIST_DIR="dist"
VENV=".venv"

G="\033[32m"; R="\033[31m"; N="\033[0m"
info()  { echo -e "${G}[*]${N} $*"; }
error() { echo -e "${R}[!]${N} $*"; exit 1; }

# ── system deps check ─────────────────────────────────────────────────────────
if ! python3 -c "import ensurepip" 2>/dev/null; then
    info "Installing python3-venv and python3-pip..."
    sudo apt-get install -y python3-venv python3-pip -q
fi

# ── venv (recreate if pip missing) ───────────────────────────────────────────
if [ ! -f "${VENV}/bin/pip" ]; then
    info "Creating virtualenv..."
    rm -rf "${VENV}"
    python3 -m venv --clear "${VENV}"
fi

# ── install deps ──────────────────────────────────────────────────────────────
info "Installing dependencies..."
"${VENV}/bin/pip" install --upgrade pip -q
"${VENV}/bin/pip" install -r requirements.txt pyinstaller -q

# ── build GUI ─────────────────────────────────────────────────────────────────
info "Building ${PROJECT} binary..."
"${VENV}/bin/pyinstaller" \
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
    main.py || error "GUI build failed."

# ── build CLI ─────────────────────────────────────────────────────────────────
info "Building ${PROJECT}-cli binary..."
"${VENV}/bin/pyinstaller" \
    --onefile \
    --name "${PROJECT}-cli" \
    --add-data "core:core" \
    --hidden-import flask \
    --hidden-import werkzeug \
    cli/main.py || error "CLI build failed."

# ── move binaries ─────────────────────────────────────────────────────────────
info "Moving binaries to ${BIN_DIR}/..."
mkdir -p "${BIN_DIR}"
rm -f "${BIN_DIR}/${PROJECT}" "${BIN_DIR}/${PROJECT}-cli"
mv "${DIST_DIR}/${PROJECT}"     "${BIN_DIR}/${PROJECT}"
mv "${DIST_DIR}/${PROJECT}-cli" "${BIN_DIR}/${PROJECT}-cli"
chmod +x "${BIN_DIR}/${PROJECT}" "${BIN_DIR}/${PROJECT}-cli"
rm -rf build dist *.spec

info "Build complete:"
ls -lh "${BIN_DIR}/${PROJECT}" "${BIN_DIR}/${PROJECT}-cli"
