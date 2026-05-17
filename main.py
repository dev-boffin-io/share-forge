#!/usr/bin/env python3
# main.py — share-forge entry point
# Usage:
#   python main.py           → GUI
#   python main.py --cli     → CLI (pass remaining args to CLI)
#   python main.py --cli /path/to/dir -p 8080

import sys
import os


def main():
    args = sys.argv[1:]

    if "--cli" in args:
        args.remove("--cli")
        sys.argv = [sys.argv[0]] + args
        from cli.main import main as cli_main
        cli_main()
    else:
        from gui.main_window import run_gui
        run_gui()


if __name__ == "__main__":
    main()
