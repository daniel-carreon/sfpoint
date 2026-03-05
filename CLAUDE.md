# CLAUDE.md — SFPoint Development Instructions

## What is SFPoint?

SFPoint is a macOS screen annotation tool that replaces Presentify ($7). Toggle-based shortcuts: Ctrl+key activates/deactivates tools. Draw temporary arrows, rectangles, circles, freehand lines, text, laser pointer, or highlighter on a transparent fullscreen overlay. Annotations auto-fade after 3 seconds. Uses SF brand colors (morado #8B5CF6 + ambar #F59E0B).

## Quick Start

```bash
# Background (recommended)
sfpoint          # Start (kills previous instance first)
sfpoint-off      # Stop

# Or direct
cd ~/Developer/software/sfpoint
PYTHONPATH=venv/lib/python3.12/site-packages python3.12 main.py
```

## macOS Permissions Required

- **Accessibility**: System Settings > Privacy & Security > Accessibility > add your Terminal/IDE
- **Input Monitoring**: Required for pynput global hotkeys — add your Terminal/IDE

## Usage

| Action | Shortcut |
|--------|----------|
| Arrow | Ctrl+A (toggle) |
| Rectangle | Ctrl+R (toggle) |
| Circle | Ctrl+C (toggle) |
| Freehand | Ctrl+F (toggle) |
| Text | Ctrl+T (toggle, type + Enter to place) |
| Laser pointer | Ctrl+P (toggle, ambar Google Slides-style) |
| Hide/show toolbar | Ctrl+H |
| Settings panel | Ctrl+S |
| Undo | Cmd+Z |
| Clear all | Cmd+Shift+Z |
| Deactivate | Esc |

All tool shortcuts are toggle-based: press once to activate, press again (or Esc) to deactivate.

## Project Structure

```
sfpoint/
├── main.py              # Entry point, wires signals
├── config.py            # Colors, shortcuts, timing, persistence
├── core/
│   ├── hotkey.py        # Global hotkeys (pynput, toggle-based Ctrl+key)
│   └── drawing.py       # Shape engine (Annotation dataclass + ShapeRenderer)
├── ui/
│   ├── canvas.py        # Fullscreen transparent overlay with click-through
│   ├── toolbar.py       # Floating pill toolbar (current tool + color)
│   └── settings.py      # Settings panel (rebindable shortcuts)
├── logo.png
├── logo_small.png
├── settings.json        # Persisted custom shortcuts (auto-created)
├── start_sfpoint.sh     # Background launcher script
├── PRP.md               # Project Requirements Plan (build blueprint)
└── requirements.txt     # PyQt6, pynput, pyobjc-framework-Cocoa, numpy
```

## Critical Implementation Details

### 1. Click-Through Toggle (PyObjC)
The canvas overlay uses `setIgnoresMouseEvents_` to toggle between:
- **Inactive**: clicks pass through to apps below (default)
- **Active**: canvas captures mouse for drawing

### 2. Qt Signal Threading
pynput emits from its own thread. ALL signals use explicit `Qt.ConnectionType.QueuedConnection` for thread safety.

### 3. Floating Window (no focus steal)
PyObjC `NSFloatingWindowLevel` + `NSWindowStyleMaskNonactivatingPanel` ensures overlay never steals focus from other apps.

### 4. Toggle-Based Shortcuts
Ctrl+key toggles tool on/off. Pressing same shortcut again deactivates. Pressing different tool shortcut switches. Esc always deactivates.

### 5. Settings Persistence
Custom shortcuts saved to `settings.json` via `config.load_shortcuts()` / `config.save_shortcuts()`. Settings panel (Ctrl+S) allows live rebinding with conflict resolution.

### 6. Auto-Fade
Annotations persist for 3 seconds (`FADE_DELAY`), then fade over 0.5 seconds (`FADE_DURATION`) via 60 FPS QTimer.

### 7. Laser Pointer
Ambar-colored (#F59E0B) Google Slides-style pointer with:
- Radial gradient dot (white core -> ambar glow)
- Connected trail with quadratic alpha falloff (30 points)
- Warm halo effect

## Brand Colors

| Color | Hex | Use |
|-------|-----|-----|
| Morado | #8B5CF6 | Default annotation color |
| Ambar | #F59E0B | Laser pointer + palette option |
| Red | #EF4444 | Palette option |
| Green | #22C55E | Palette option |
| White | #FFFFFF | Palette option |

## Dependencies

- Python 3.12+ (uses `list[]` generics and `|` union syntax)
- PyQt6 — UI framework
- pynput — global hotkey detection
- pyobjc-framework-Cocoa — native macOS window management
- numpy — audio/math utilities

## Common Issues

| Problem | Solution |
|---------|----------|
| Tool doesn't activate | Grant Accessibility + Input Monitoring to your Terminal |
| Overlay steals focus | Verify pyobjc-framework-Cocoa installed |
| Font warning in console | Uses `.AppleSystemUIFont` (system font), warning is cosmetic |
| `sfpoint` alias not found | Run `source ~/.zshrc` after adding aliases |
| Python version error | Requires 3.12+, check with `python3 --version` |
