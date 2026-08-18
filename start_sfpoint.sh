#!/bin/bash
# Dev-mode launcher. For daily use install the .app: bash build.sh --install
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
exec ./venv/bin/python main.py
