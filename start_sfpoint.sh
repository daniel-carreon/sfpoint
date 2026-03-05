#!/bin/bash
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
export PYTHONPATH="/Users/danielcarreon/Developer/software/sfpoint/venv/lib/python3.12/site-packages"
cd /Users/danielcarreon/Developer/software/sfpoint
exec /opt/homebrew/Cellar/python@3.12/3.12.13/Frameworks/Python.framework/Versions/3.12/Resources/Python.app/Contents/MacOS/Python main.py
