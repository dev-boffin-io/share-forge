# share-forge

> Local network file server with GUI — part of the **Forge Suite**

Browse, upload, and download files over LAN via a clean web UI. Supports folder ZIP download, individual file download, file upload, and directory browsing.

---

## Project Structure

```
share-forge/
├── assets/
│   └── share-forge.png      # App icon (used for .desktop entry)
├── core/
│   ├── __init__.py
│   ├── config.py            # Constants, ignored dirs, IP helper
│   ├── server.py            # Flask app factory (routes, MIME handling)
│   └── template.py          # HTML template (file listing UI)
├── gui/
│   ├── __init__.py
│   └── main_window.py       # PyQt6 GUI (multi-server, tray, log)
├── cli/
│   ├── __init__.py
│   └── main.py              # CLI entry point (argparse, --kill, --auto-port)
├── main.py                  # Dispatcher: GUI (default) or --cli
├── requirements.txt
├── Makefile                 # Linux: build + install + .desktop entry
├── build.sh                 # Linux build script
├── build.bat                # Windows build script (cmd)
└── build.ps1                # Windows build script (PowerShell)
```

---

## Usage

### GUI
```bash
python main.py
```

### CLI
```bash
python main.py --cli [directory] [-p PORT] [--auto-port] [--kill]

# Examples
python main.py --cli                    # serve current dir on :5000
python main.py --cli /home/user/docs    # serve specific dir
python main.py --cli -p 8080            # custom port
python main.py --cli --auto-port        # pick next free port automatically
python main.py --cli --kill             # kill any running instance
```

---

## Build & Install (Linux)

```bash
# Build GUI + CLI binaries → ./bin/
make build

# Install binary + desktop entry + icon
make install

# Uninstall
make uninstall

# Clean build artefacts
make clean

# Options
make build DEBUG=1          # verbose PyInstaller output
make install PREFIX=/usr    # system-wide install
```

After `make install`:
- `~/.local/bin/share-forge` — GUI binary
- `~/.local/bin/share-forge-cli` — CLI binary
- `~/.local/share/applications/share-forge.desktop` — app menu entry
- `~/.local/share/icons/hicolor/256x256/apps/share-forge.png` — icon

---

## Build (Windows)

**CMD:**
```bat
build.bat
```

**PowerShell:**
```powershell
.\build.ps1
```

Output: `bin\share-forge.exe` and `bin\share-forge-cli.exe`

---

## Requirements

- Python 3.11+
- Flask, Werkzeug, PyQt6

```bash
pip install -r requirements.txt
```
