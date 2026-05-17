# share-forge

> Local network file server with GUI — part of the **Forge Suite**

Browse, upload, and download files over LAN via a clean web UI. Supports folder ZIP download, file upload, and directory browsing.

## Project Structure

```
share-forge/
├── core/
│   ├── __init__.py
│   ├── config.py        # Constants, ignored dirs, IP helper
│   ├── server.py        # Flask app factory (routes)
│   └── template.py      # HTML template
├── gui/
│   ├── __init__.py
│   └── main_window.py   # PyQt6 GUI (start/stop, log, browser open)
├── cli/
│   ├── __init__.py
│   └── main.py          # CLI entry point (argparse)
├── main.py              # Dispatcher: GUI (default) or --cli
├── requirements.txt
└── build.sh
```

## Usage

### GUI
```bash
python main.py
```

### CLI
```bash
python main.py --cli [directory] [-p PORT]

# Examples
python main.py --cli                    # serve current dir on :5000
python main.py --cli /home/user/docs    # serve specific dir
python main.py --cli -p 8080            # custom port
```

## Build (PyInstaller)
```bash
chmod +x build.sh
./build.sh
# → dist/share-forge       (GUI binary)
# → dist/share-forge-cli   (CLI binary)
```

## Requirements
- Python 3.11+
- Flask, Werkzeug, PyQt6
