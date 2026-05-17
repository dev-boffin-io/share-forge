# build.ps1 — share-forge PyInstaller build (Windows / PowerShell)
# Run with: powershell -ExecutionPolicy Bypass -File build.ps1
$ErrorActionPreference = "Stop"

$PROJECT  = "share-forge"
$DIST_DIR = "dist"
$BIN_DIR  = "bin"

Write-Host "================================================"
Write-Host "  $PROJECT -- Build Script (Windows / PS)"
Write-Host "================================================"

# ── venv ──────────────────────────────────────────
if (-not (Test-Path ".venv")) {
    Write-Host "[*] Creating .venv..."
    python -m venv .venv
}

& .venv\Scripts\python.exe -m pip install --upgrade pip -q
& .venv\Scripts\pip.exe install -r requirements.txt pyinstaller -q
Write-Host "[*] Dependencies installed."

# ── GUI binary ────────────────────────────────────
Write-Host "[*] Building GUI binary..."
& .venv\Scripts\pyinstaller.exe `
    --onefile `
    --name $PROJECT `
    --windowed `
    --add-data "core;core" `
    --add-data "gui;gui" `
    --hidden-import PyQt6.QtWidgets `
    --hidden-import PyQt6.QtCore `
    --hidden-import PyQt6.QtGui `
    --hidden-import flask `
    --hidden-import werkzeug `
    main.py
if ($LASTEXITCODE -ne 0) { Write-Error "[!] GUI build failed."; exit 1 }

# ── CLI binary ────────────────────────────────────
Write-Host "[*] Building CLI binary..."
& .venv\Scripts\pyinstaller.exe `
    --onefile `
    --name "$PROJECT-cli" `
    --add-data "core;core" `
    --hidden-import flask `
    --hidden-import werkzeug `
    cli\main.py
if ($LASTEXITCODE -ne 0) { Write-Error "[!] CLI build failed."; exit 1 }

# ── Move binaries to bin\ ─────────────────────────
Write-Host "[*] Moving binaries to $BIN_DIR\..."
New-Item -ItemType Directory -Force -Path $BIN_DIR | Out-Null
Move-Item -Force "$DIST_DIR\$PROJECT.exe"     "$BIN_DIR\$PROJECT.exe"
Move-Item -Force "$DIST_DIR\$PROJECT-cli.exe" "$BIN_DIR\$PROJECT-cli.exe"

# ── Cleanup ───────────────────────────────────────
Write-Host "[*] Cleaning up build artifacts..."
Remove-Item -Recurse -Force build, dist -ErrorAction SilentlyContinue
Remove-Item -Force "$PROJECT.spec", "$PROJECT-cli.spec" -ErrorAction SilentlyContinue

Write-Host "================================================"
Write-Host "  Build complete:"
Get-Item "$BIN_DIR\$PROJECT.exe", "$BIN_DIR\$PROJECT-cli.exe" |
    Format-Table Name, @{L="Size (KB)"; E={[math]::Round($_.Length/1KB, 1)}}
Write-Host "================================================"
