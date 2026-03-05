# CLAUDE.md — SFPoint: Complete Setup & Development Guide

> This file is designed for AI agents. If you just cloned this repo, follow the **Automated Setup** section to get SFPoint running end-to-end without human intervention.

## What is SFPoint?

SFPoint is a macOS screen annotation tool (Presentify replacement). Toggle-based Ctrl+key shortcuts activate/deactivate tools. Draw temporary arrows, rectangles, circles, freehand lines, text, laser pointer, or highlighter on a transparent fullscreen overlay. Annotations auto-fade after 3 seconds. Laser pointer is click-through (doesn't block mouse). SF brand colors: morado #8B5CF6, ambar #F59E0B.

---

## Automated Setup (AI Agent — Fresh Machine)

Follow these steps IN ORDER. Each step depends on the previous one.

### Step 1: Verify Prerequisites

```bash
# Check macOS version (needs 15+)
sw_vers -productVersion

# Check if Homebrew is installed
which brew || echo "INSTALL HOMEBREW FIRST: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""

# Check if Python 3.12+ is available
python3.12 --version 2>/dev/null || python3 --version
# If python3.12 not found:
# brew install python@3.12
```

**IMPORTANT:** Python 3.12+ is REQUIRED. The codebase uses `list[]` generics and `|` union syntax which are 3.10+ features, and some dependencies need 3.12.

### Step 2: Clone Repository

```bash
# Choose your install location (default: ~/Developer/software/)
mkdir -p ~/Developer/software
cd ~/Developer/software
git clone https://github.com/daniel-carreon/sfpoint.git
cd sfpoint
```

### Step 3: Create Virtual Environment

```bash
# Find the exact Python 3.12 binary path
PYTHON_BIN=$(which python3.12 2>/dev/null || find /opt/homebrew/Cellar/python@3.12 -name "Python" -path "*/Resources/Python.app/Contents/MacOS/Python" 2>/dev/null | head -1)

# If neither found, install it
if [ -z "$PYTHON_BIN" ]; then
    brew install python@3.12
    PYTHON_BIN=$(find /opt/homebrew/Cellar/python@3.12 -name "Python" -path "*/Resources/Python.app/Contents/MacOS/Python" | head -1)
fi

echo "Using Python: $PYTHON_BIN"

# Create venv with the correct Python
$PYTHON_BIN -m venv venv
```

### Step 4: Install Dependencies

```bash
# Activate and install
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

**Dependencies:** PyQt6, pynput, pyobjc-framework-Cocoa, numpy

### Step 5: Validate Installation

```bash
# Quick import test (should exit cleanly with no errors)
PYTHONPATH=venv/lib/python3.12/site-packages $PYTHON_BIN -c "
from PyQt6.QtWidgets import QApplication
from pynput import keyboard
import objc
import numpy
print('All imports OK')
"
```

If this fails, check:
- `pip list` in venv to verify packages installed
- `python3.12 --version` to verify Python version

### Step 6: Configure Shell Aliases

```bash
# Detect the exact Python binary path and site-packages for aliases
SFPOINT_DIR="$HOME/Developer/software/sfpoint"
PYTHON_BIN=$(head -1 "$SFPOINT_DIR/venv/bin/python3" | sed 's/#!//')

# If that doesn't work, find it from the venv config
if [ ! -f "$PYTHON_BIN" ]; then
    PYTHON_HOME=$(grep "home" "$SFPOINT_DIR/venv/pyvenv.cfg" | cut -d'=' -f2 | tr -d ' ')
    PYTHON_BIN="$PYTHON_HOME/python3.12"
fi

# For background execution we need the Framework Python binary (macOS GUI apps requirement)
# The venv python won't work for GUI apps run in background — we need the actual Framework binary
FRAMEWORK_PYTHON=$(find /opt/homebrew/Cellar/python@3.12 -name "Python" -path "*/Resources/Python.app/Contents/MacOS/Python" 2>/dev/null | head -1)
SITE_PACKAGES="$SFPOINT_DIR/venv/lib/python3.12/site-packages"

echo ""
echo "Add these lines to your ~/.zshrc:"
echo ""
echo "# SFPoint - Screen Annotation Tool"
echo "alias sfpoint='pkill -f \"sfpoint/main.py\" 2>/dev/null; sleep 0.5; PYTHONPATH=$SITE_PACKAGES $FRAMEWORK_PYTHON $SFPOINT_DIR/main.py &>/dev/null & disown; echo \"SFPoint running\"'"
echo "alias sfpoint-off='pkill -f \"sfpoint/main.py\" 2>/dev/null; echo \"SFPoint stopped\"'"
```

**To apply automatically (AI agent can run this):**

```bash
# Remove old sfpoint aliases if they exist
sed -i '' '/# SFPoint/d' ~/.zshrc 2>/dev/null
sed -i '' '/alias sfpoint/d' ~/.zshrc 2>/dev/null

# Detect paths
SFPOINT_DIR="$HOME/Developer/software/sfpoint"
FRAMEWORK_PYTHON=$(find /opt/homebrew/Cellar/python@3.12 -name "Python" -path "*/Resources/Python.app/Contents/MacOS/Python" 2>/dev/null | head -1)
SITE_PACKAGES="$SFPOINT_DIR/venv/lib/python3.12/site-packages"

# Append aliases
cat >> ~/.zshrc << ALIASES

# SFPoint - Screen Annotation Tool
alias sfpoint='pkill -f "sfpoint/main.py" 2>/dev/null; sleep 0.5; PYTHONPATH=$SITE_PACKAGES $FRAMEWORK_PYTHON $SFPOINT_DIR/main.py &>/dev/null & disown; echo "SFPoint running"'
alias sfpoint-off='pkill -f "sfpoint/main.py" 2>/dev/null; echo "SFPoint stopped"'
ALIASES

echo "Aliases added. Run: source ~/.zshrc"
```

**WHY FRAMEWORK_PYTHON?** macOS requires the Framework Python binary (not the venv symlink) for GUI applications that run in background with `& disown`. The venv `python3` symlink will fail silently for background GUI processes. The Framework binary path looks like:
`/opt/homebrew/Cellar/python@3.12/X.Y.Z/Frameworks/Python.framework/Versions/3.12/Resources/Python.app/Contents/MacOS/Python`

### Step 7: macOS Permissions

**CRITICAL — SFPoint will NOT work without these permissions.**

The user must manually grant these (cannot be automated):

1. **System Settings > Privacy & Security > Accessibility**
   - Add your Terminal app (Terminal.app, iTerm2, VS Code, Warp, etc.)
   - This enables: global hotkeys, overlay window interaction

2. **System Settings > Privacy & Security > Input Monitoring**
   - Add the SAME Terminal app
   - This enables: pynput keyboard listener (Ctrl+key detection)

**How to verify permissions are granted:**
```bash
# Run SFPoint in foreground to see any permission errors
cd ~/Developer/software/sfpoint
source venv/bin/activate
python3 main.py
# If hotkeys don't work -> permissions missing
# If you see "SFPoint running." and hotkeys work -> all good
# Ctrl+C to quit
```

**If permissions dialog doesn't appear:** Sometimes macOS doesn't prompt. Go to System Settings manually, find your Terminal app in both Accessibility and Input Monitoring, and toggle it ON.

### Step 8: First Run

```bash
# Foreground test (to verify everything works)
cd ~/Developer/software/sfpoint
source venv/bin/activate
python3 main.py

# You should see:
# "SFPoint running."
# A small toolbar pill at the bottom center of screen
# Try Ctrl+A to activate arrow tool, draw on screen, Esc to deactivate
# Ctrl+C to quit

# Background run (after verification)
source ~/.zshrc
sfpoint
```

### Step 9: Verify All Features

```
Ctrl+A -> Arrow tool (draw arrow on screen, auto-fades in 3s)
Ctrl+R -> Rectangle
Ctrl+C -> Circle
Ctrl+F -> Freehand drawing
Ctrl+T -> Text (click to place cursor, type, Enter to commit)
Ctrl+P -> Laser pointer (ambar dot follows cursor, click-through, morado ripple on click)
Ctrl+H -> Hide/show toolbar
Ctrl+S -> Settings panel (rebind shortcuts)
Cmd+Z  -> Undo last annotation
Cmd+Shift+Z -> Clear all annotations
Esc    -> Deactivate current tool
```

---

## Usage Details

### Tool Shortcuts (Toggle-Based)

| Action | Shortcut |
|--------|----------|
| Arrow | Ctrl+A (toggle) |
| Rectangle | Ctrl+R (toggle) |
| Circle | Ctrl+C (toggle) |
| Freehand | Ctrl+F (toggle) |
| Text | Ctrl+T (toggle, type + Enter to place) |
| Laser pointer | Ctrl+P (toggle, click-through, ambar dot + morado ripple on click) |
| Hide/show toolbar | Ctrl+H |
| Settings panel | Ctrl+S |
| Undo | Cmd+Z |
| Clear all | Cmd+Shift+Z |
| Deactivate | Esc |

### Laser Pointer Behavior
- **Click-through**: laser does NOT block mouse clicks, right-click, drag, etc.
- **Cursor tracking**: follows cursor via QCursor.pos() polling (no mouse capture)
- **Ambar dot**: subtle 5px dot with soft 14px glow halo
- **Trail**: thin fading line (18 points max), decays when mouse stops
- **Ripple on click**: morado (#8B5CF6) expanding ring with ease-out animation (0.4s)
- Detected via pynput mouse listener running alongside keyboard listener

---

## Project Structure

```
sfpoint/
├── main.py              # Entry point, wires all signals with QueuedConnection
├── config.py            # Colors, shortcuts, timing, persistence (settings.json)
├── core/
│   ├── hotkey.py        # Global hotkeys (pynput, toggle-based Ctrl+key)
│   └── drawing.py       # Shape engine (Annotation dataclass + ShapeRenderer)
├── ui/
│   ├── canvas.py        # Fullscreen transparent overlay with click-through
│   ├── toolbar.py       # Floating pill toolbar (current tool + color)
│   └── settings.py      # Settings panel (rebindable shortcuts)
├── logo.png             # SFPoint logo (used in README)
├── logo_small.png       # Small logo (used in toolbar pill)
├── settings.json        # Persisted custom shortcuts (auto-created, gitignored)
├── start_sfpoint.sh     # Background launcher script
├── PRP.md               # Project Requirements Plan (build blueprint for AI)
├── CLAUDE.md            # This file
├── README.md            # Public-facing documentation
└── requirements.txt     # PyQt6, pynput, pyobjc-framework-Cocoa, numpy
```

---

## Critical Implementation Details

### 1. Click-Through Toggle (PyObjC)
The canvas overlay uses `NSWindow.setIgnoresMouseEvents_()` to toggle between:
- **Inactive**: clicks pass through to apps below (default state)
- **Active (non-laser)**: canvas captures mouse for drawing shapes
- **Active (laser)**: stays click-through, tracks cursor via polling

### 2. Qt Signal Threading
pynput keyboard and mouse listeners run on their own threads. ALL signals use explicit `Qt.ConnectionType.QueuedConnection` for thread safety. The laser ripple uses a dedicated `pyqtSignal(float, float)` to safely marshal click coordinates from pynput thread to Qt main thread.

### 3. Floating Window (no focus steal)
PyObjC `NSFloatingWindowLevel` + `NSWindowStyleMaskNonactivatingPanel` ensures overlay never steals focus. Canvas is at level `NSFloatingWindowLevel + 1`, toolbar at `NSFloatingWindowLevel`, settings at `NSFloatingWindowLevel + 2`.

### 4. Background Execution
macOS requires the Framework Python binary (not venv symlink) for background GUI processes. The alias uses explicit `PYTHONPATH` to the venv's site-packages + the Framework Python binary path, with `& disown` for detachment.

### 5. Settings Persistence
Custom shortcuts saved to `settings.json` via `config.load_shortcuts()` / `config.save_shortcuts()`. Settings panel (Ctrl+S) allows live rebinding with automatic conflict resolution. File is gitignored (user-specific).

---

## Brand Colors

| Color | Hex | Use |
|-------|-----|-----|
| Morado | #8B5CF6 | Default annotations, click ripple |
| Ambar | #F59E0B | Laser pointer dot + trail |
| Red | #EF4444 | Palette option |
| Green | #22C55E | Palette option |
| White | #FFFFFF | Palette option |

---

## Common Issues

| Problem | Solution |
|---------|----------|
| Tool doesn't activate | Grant Accessibility + Input Monitoring to your Terminal |
| Overlay steals focus | Verify pyobjc-framework-Cocoa installed: `pip install pyobjc-framework-Cocoa` |
| Font warning in console | Cosmetic — uses `.AppleSystemUIFont` (macOS system font) |
| `sfpoint` alias not found | Run `source ~/.zshrc` after adding aliases |
| Python version error | Requires 3.12+ — `brew install python@3.12` |
| Background launch fails silently | Must use Framework Python binary, not venv symlink (see Step 6) |
| Laser blocks clicks | Update to latest version — laser now uses click-through mode |
| No ripple on click | pynput mouse listener needs Input Monitoring permission |
| Permissions dialog never appears | Manually add Terminal to Accessibility + Input Monitoring in System Settings |
