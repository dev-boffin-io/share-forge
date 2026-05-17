#!/usr/bin/env python3
# cli/main.py
import argparse
import os
import sys
import signal

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from core import create_app, DEFAULT_PORT, DEFAULT_HOST, get_local_ip, is_port_free, find_free_port

PROC_NAME = "share-forge"


def _kill_existing() -> bool:
    """Kill any running share-forge / share-forge-cli processes. Returns True if any killed."""
    import subprocess
    killed = False
    for name in (PROC_NAME, f"{PROC_NAME}-cli"):
        try:
            result = subprocess.run(
                ["pkill", "-f", name],
                capture_output=True
            )
            if result.returncode == 0:
                print(f"[*] Killed: {name}")
                killed = True
        except FileNotFoundError:
            # pkill not available (Windows?) — fallback
            pass
    return killed


def parse_args():
    parser = argparse.ArgumentParser(
        prog=PROC_NAME,
        description="share-forge — local network file server (Forge Suite)"
    )
    parser.add_argument(
        "directory", nargs="?", default=".",
        help="Directory to serve (default: current directory)"
    )
    parser.add_argument(
        "-p", "--port", type=int, default=DEFAULT_PORT,
        help=f"Port to listen on (default: {DEFAULT_PORT})"
    )
    parser.add_argument(
        "--host", default=DEFAULT_HOST,
        help=f"Host to bind (default: {DEFAULT_HOST})"
    )
    parser.add_argument(
        "--kill", action="store_true",
        help="Kill any running share-forge instance and exit"
    )
    parser.add_argument(
        "--auto-port", action="store_true",
        help="Auto-select next free port if requested port is in use"
    )
    return parser.parse_args()


def main():
    args = parse_args()

    # ── kill mode ──────────────────────────────────────────────────────────
    if args.kill:
        if _kill_existing():
            print("[*] Done.")
        else:
            print("[!] No running share-forge process found.")
        sys.exit(0)

    # ── validate directory ─────────────────────────────────────────────────
    directory = os.path.abspath(args.directory)
    if not os.path.isdir(directory):
        print(f"[!] Not a directory: {directory}", file=sys.stderr)
        sys.exit(1)

    # ── port check ─────────────────────────────────────────────────────────
    port = args.port
    if not is_port_free(port):
        if args.auto_port:
            port = find_free_port(port + 1)
            print(f"[!] Port {args.port} in use — using {port} instead.")
        else:
            suggested = find_free_port(port + 1)
            print(f"[!] Port {port} is already in use.", file=sys.stderr)
            print(f"    Run with --kill to stop the existing instance, or", file=sys.stderr)
            print(f"    use -p {suggested}  or  --auto-port", file=sys.stderr)
            sys.exit(1)

    local_ip = get_local_ip()
    print("=" * 52)
    print(f"  share-forge  |  Forge Suite")
    print("=" * 52)
    print(f"  Directory : {directory}")
    print(f"  Local     : http://127.0.0.1:{port}")
    print(f"  Network   : http://{local_ip}:{port}")
    print("  Press Ctrl+C to stop")
    print("=" * 52)

    app = create_app(directory)
    try:
        app.run(host=args.host, port=port, debug=False, use_reloader=False)
    except KeyboardInterrupt:
        print("\n[*] Server stopped.")


if __name__ == "__main__":
    main()
