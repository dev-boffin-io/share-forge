# core/config.py
import os
import sys
import socket

DEFAULT_PORT = 5000
DEFAULT_HOST = "0.0.0.0"

IGNORED_DIRS = {'.venv', '.win_venv', '__pycache__', '.git', '.idea', 'node_modules'}


def get_self_binary_names() -> set[str]:
    names: set[str] = set()
    if getattr(sys, 'frozen', False):
        exe = os.path.basename(sys.executable)
        names.add(exe)
        base = exe.replace('-cli', '').replace('.exe', '')
        names.add(base)
        names.add(base + '-cli')
        names.add(base + '.exe')
        names.add(base + '-cli.exe')
    return names


def get_local_ip() -> str:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


def is_port_free(port: int, host: str = "127.0.0.1") -> bool:
    """Return True if the port is available to bind."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            s.bind((host, port))
            return True
        except OSError:
            return False


def find_free_port(start: int = DEFAULT_PORT, host: str = "127.0.0.1") -> int:
    """Return start if free, otherwise next available port."""
    port = start
    while port < 65535:
        if is_port_free(port, host):
            return port
        port += 1
    return start
