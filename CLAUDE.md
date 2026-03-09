# CLAUDE.md — SFPoint: Complete Setup & Development Guide

> This file is designed for AI agents. If you just cloned this repo, follow the **Automated Setup** section to get SFPoint running end-to-end without human intervention.

## What is SFPoint?

SFPoint is a macOS screen annotation tool (Presentify replacement). Toggle-based Ctrl+key shortcuts activate/deactivate tools. Draw temporary arrows, rectangles, circles, freehand lines, text, laser pointer, or highlighter on a transparent fullscreen overlay. Annotations auto-fade after 3 seconds. Laser pointer is click-through (doesn't block mouse). SF brand colors: morado #8B5CF6, ambar #F59E0B.

---

## Quick Start (Dev Mode)

```bash
# 1. Clone
git clone https://github.com/daniel-carreon/sfpoint.git
cd sfpoint

# 2. Create virtual environment
python3 -m venv venv
source venv/bin/activate

# 3. Install Python dependencies
pip install -r requirements.txt

# 4. Run
python3 main.py
```

## Build Desktop App (.app bundle)

```bash
# Build SFPoint.app (generates icns, builds with PyInstaller, signs ad-hoc)
bash build.sh

# Install to Applications (MUST use ditto, not cp -r)
ditto dist/SFPoint.app /Applications/SFPoint.app

# Remove quarantine if needed
xattr -cr /Applications/SFPoint.app
```

The .app bundle is self-contained (~90MB). No Python, no venv, no terminal needed.
The app lives in the menu bar (no Dock icon).

### Build Requirements
- Python 3.12+ with venv
- PyInstaller (installed automatically by build.sh)

## macOS Permissions Required

**CRITICAL — SFPoint will NOT work without these permissions.**

- **Accessibility**: System Settings > Privacy & Security > Accessibility > add SFPoint.app (or your Terminal for dev mode)
- **Input Monitoring**: System Settings > Privacy & Security > Input Monitoring > add SFPoint.app (or your Terminal for dev mode)

**If permissions dialog doesn't appear:** Go to System Settings manually and toggle the app ON.

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
├── main.py              # Entry point — tray icon, launch-at-login, signal wiring
├── config.py            # All configuration constants (UI, tools, paths, bundle detection)
├── sfpoint.spec         # PyInstaller spec for building .app bundle
├── build.sh             # One-shot build script (icns → PyInstaller → sign)
├── core/
│   ├── hotkey.py        # Global hotkeys (pynput, toggle-based Option+key)
│   └── drawing.py       # Shape engine (Annotation dataclass + ShapeRenderer)
├── ui/
│   ├── canvas.py        # Fullscreen transparent overlay with click-through
│   ├── toolbar.py       # Floating pill toolbar (current tool + color)
│   └── settings.py      # Settings panel (rebindable shortcuts)
├── logo.png             # SFPoint logo (full size, used for .icns generation)
├── logo_small.png       # Small logo (22x22 for menu bar + toolbar pill)
├── SFPoint.icns         # macOS app icon (generated from logo.png)
├── requirements.txt     # PyQt6, pynput, pyobjc-framework-Cocoa, numpy
├── PRP.md               # Project Requirements Plan (build blueprint for AI)
├── CLAUDE.md            # This file
└── README.md            # Public-facing documentation
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

### 4. Bundle vs Dev Mode (config.py)
`config.py` detects `sys.frozen` to switch between dev and .app bundle:
- **Dev mode**: assets and data live in the project root directory
- **Bundle mode**: read-only assets (logo) come from `sys._MEIPASS`, writable data (settings.json) goes to `~/Library/Application Support/SFPoint/`

### 5. Desktop App Features (main.py)
- **System Tray**: QSystemTrayIcon in menu bar with Settings, "Start with macOS" toggle, Quit
- **Launch at Login**: Creates/removes a LaunchAgent plist in `~/Library/LaunchAgents/`
- **Hide from Dock**: `NSApplicationActivationPolicyAccessory` via PyObjC (MUST be set AFTER all windows are shown)

### 6. Settings Persistence
Custom shortcuts saved to `settings.json` via `config.load_shortcuts()` / `config.save_shortcuts()`. Settings panel (Option+S) allows live rebinding with automatic conflict resolution. In bundle mode, settings go to `~/Library/Application Support/SFPoint/settings.json`.

### 7. Building the .app (IMPORTANT)
- Use `ditto` (not `cp -r`) to copy .app to /Applications — `cp -r` corrupts bundle metadata causing segfaults
- The .icns is auto-generated from logo.png by build.sh if missing
- Ad-hoc signing (`codesign --force --deep --sign -`) is sufficient for personal use
- Remove quarantine after install: `xattr -cr /Applications/SFPoint.app`

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
| Tool doesn't activate | Grant Accessibility + Input Monitoring to SFPoint.app (or Terminal in dev mode) |
| Overlay steals focus | Verify pyobjc-framework-Cocoa installed: `pip install pyobjc-framework-Cocoa` |
| Font warning in console | Cosmetic — uses `.AppleSystemUIFont` (macOS system font) |
| Python version error | Requires 3.12+ — `brew install python@3.12` |
| Laser blocks clicks | Update to latest version — laser now uses click-through mode |
| No ripple on click | pynput mouse listener needs Input Monitoring permission |
| Permissions dialog never appears | Manually add SFPoint.app to Accessibility + Input Monitoring in System Settings |
| .app crashes (segfault) | Was copied with `cp -r` instead of `ditto`. Reinstall with `ditto` |
| .app blocked by macOS | Run `xattr -cr /Applications/SFPoint.app` to remove quarantine |
