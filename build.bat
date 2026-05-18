@echo off
setlocal enabledelayedexpansion

set PROJECT=share-forge
set DIST_DIR=dist
set BIN_DIR=bin

echo ================================================
echo   %PROJECT% -- Build Script (Windows)
echo ================================================

:: ── venv ──────────────────────────────────────────
if not exist .venv (
    echo [*] Creating .venv...
    python -m venv .venv
    if errorlevel 1 (
        echo [!] Failed to create venv. Is Python installed?
        exit /b 1
    )
)

call .venv\Scripts\activate.bat
python -m pip install --upgrade pip -q
pip install -r requirements.txt pyinstaller -q
echo [*] Dependencies installed.

:: ── GUI binary ────────────────────────────────────
echo [*] Building GUI binary...
pyinstaller ^
    --onefile ^
    --name "%PROJECT%" ^
    --windowed ^
    --add-data "core;core" ^
    --add-data "gui;gui" ^
    --hidden-import PyQt6.QtWidgets ^
    --hidden-import PyQt6.QtCore ^
    --hidden-import PyQt6.QtGui ^
    --hidden-import flask ^
    --hidden-import werkzeug ^
    main.py
if errorlevel 1 ( echo [!] GUI build failed. & exit /b 1 )

:: ── CLI binary ────────────────────────────────────
echo [*] Building CLI binary...
pyinstaller ^
    --onefile ^
    --name "%PROJECT%-cli" ^
    --add-data "core;core" ^
    --hidden-import flask ^
    --hidden-import werkzeug ^
    cli\main.py
if errorlevel 1 ( echo [!] CLI build failed. & exit /b 1 )

:: ── Move binaries to bin\ ─────────────────────────
echo [*] Moving binaries to %BIN_DIR%\...
if not exist %BIN_DIR% mkdir %BIN_DIR%
if exist "%BIN_DIR%\%PROJECT%.exe"     del /Q "%BIN_DIR%\%PROJECT%.exe"
if exist "%BIN_DIR%\%PROJECT%-cli.exe" del /Q "%BIN_DIR%\%PROJECT%-cli.exe"
move /Y "%DIST_DIR%\%PROJECT%.exe"     "%BIN_DIR%\%PROJECT%.exe"
move /Y "%DIST_DIR%\%PROJECT%-cli.exe" "%BIN_DIR%\%PROJECT%-cli.exe"

:: ── Cleanup ───────────────────────────────────────
echo [*] Cleaning up build artifacts...
if exist build  rmdir /S /Q build
if exist dist   rmdir /S /Q dist
if exist "%PROJECT%.spec"     del /Q "%PROJECT%.spec"
if exist "%PROJECT%-cli.spec" del /Q "%PROJECT%-cli.spec"

echo ================================================
echo   Build complete:
dir /B "%BIN_DIR%\%PROJECT%.exe" "%BIN_DIR%\%PROJECT%-cli.exe"
echo ================================================
