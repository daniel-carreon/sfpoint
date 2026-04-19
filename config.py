import os
import sys
import json
from PyQt6.QtGui import QColor

# --- Bundle vs Dev Mode ---
IS_BUNDLE = getattr(sys, "frozen", False)

if IS_BUNDLE:
    # Read-only assets come from the PyInstaller temp dir
    _ASSETS_DIR = sys._MEIPASS
    # Writable data (settings.json) goes to ~/Library/Application Support/SFPoint/
    APP_DATA_DIR = os.path.join(os.path.expanduser("~"), "Library", "Application Support", "SFPoint")
    os.makedirs(APP_DATA_DIR, exist_ok=True)
else:
    _ASSETS_DIR = os.path.dirname(__file__)
    APP_DATA_DIR = os.path.dirname(__file__)

# --- Brand Colors ---
COLOR_MORADO = QColor(140, 39, 241)      # #8C27F1
COLOR_AMBAR = QColor(245, 158, 11)       # #F59E0B
COLOR_RED = QColor(239, 68, 68)          # #EF4444
COLOR_GREEN = QColor(34, 197, 94)        # #22C55E
COLOR_WHITE = QColor(255, 255, 255)      # #FFFFFF

# Ordered palette — keys 1-5
COLOR_PALETTE = [COLOR_MORADO, COLOR_AMBAR, COLOR_RED, COLOR_GREEN, COLOR_WHITE]
DEFAULT_COLOR_INDEX = 0  # morado (annotations default)

# --- Tools ---
TOOL_ARROW = "arrow"
TOOL_RECT = "rect"
TOOL_CIRCLE = "circle"
TOOL_FREEHAND = "freehand"
TOOL_TEXT = "text"
TOOL_LASER = "laser"
TOOL_HIGHLIGHTER = "highlighter"

# Ctrl+key shortcut mapping (toggle-based)
TOOL_SHORTCUTS = {
    "a": TOOL_ARROW,
    "r": TOOL_RECT,
    "c": TOOL_CIRCLE,
    "f": TOOL_FREEHAND,
    "t": TOOL_TEXT,
    "p": TOOL_LASER,       # Ctrl+P = pointer/laser
}

# Special shortcuts (not tools)
SHORTCUT_HIDE_TOOLBAR = "h"   # Ctrl+H
SHORTCUT_SETTINGS = "s"       # Ctrl+S

DEFAULT_TOOL = TOOL_ARROW

# --- Stroke ---
STROKE_THIN = 2.0
STROKE_MEDIUM = 3.0
STROKE_THICK = 5.0
STROKE_EXTRA = 8.0
STROKE_HEAVY = 12.0
STROKE_HIGHLIGHTER = 20.0
DEFAULT_STROKE = STROKE_MEDIUM
STROKE_STEPS = [STROKE_THIN, STROKE_MEDIUM, STROKE_THICK, STROKE_EXTRA, STROKE_HEAVY]

# --- Fade ---
FADE_DELAY = 3.0        # seconds before fade starts
FADE_DURATION = 0.5      # seconds for fade animation
CANVAS_FPS = 60          # repaint rate

# --- Laser (neon bloom — Google Slides-inspired size) ---
LASER_DOT_RADIUS = 7.5
LASER_GLOW_RADIUS = 21.0
LASER_TRAIL_LENGTH = 18  # short, clean trail
LASER_COLOR = COLOR_AMBAR  # ambar pointer (default)
LASER_COLOR_MORADO = COLOR_MORADO  # morado pointer (alt)

# Laser states: 0=off, 1=ambar, 2=morado (cycles on Ctrl+P presses)
LASER_STATE_OFF = 0
LASER_STATE_AMBAR = 1
LASER_STATE_MORADO = 2
LASER_COLORS = {LASER_STATE_AMBAR: COLOR_AMBAR, LASER_STATE_MORADO: COLOR_MORADO}

# --- Arrow Head ---
ARROW_HEAD_LENGTH = 14.0
ARROW_HEAD_ANGLE = 25.0  # degrees

# --- Text ---
TEXT_FONT_SIZE = 24

# --- Toolbar (pill-style, reused from SFlow) ---
TOOLBAR_HEIGHT = 34
TOOLBAR_WIDTH = 180
TOOLBAR_OPACITY = 0.90
TOOLBAR_CORNER_RADIUS = 17
TOOLBAR_MARGIN_BOTTOM = 14
TOOLBAR_ICON_SIZE = 16

# --- Logo ---
LOGO_PATH = os.path.join(_ASSETS_DIR, "logo_small.png")
LOGO_SIZE = 22

# --- Ripple (click effect on laser) ---
RIPPLE_MAX_RADIUS = 20.0
RIPPLE_DURATION = 0.55  # seconds

# --- Highlighter ---
HIGHLIGHTER_OPACITY = 0.35

# --- Settings persistence ---
SETTINGS_PATH = os.path.join(APP_DATA_DIR, "settings.json")


def load_shortcuts() -> dict:
    """Load custom shortcuts from settings.json, fallback to defaults."""
    if os.path.exists(SETTINGS_PATH):
        try:
            with open(SETTINGS_PATH) as f:
                data = json.load(f)
            return data.get("shortcuts", dict(TOOL_SHORTCUTS))
        except Exception:
            pass
    return dict(TOOL_SHORTCUTS)


def save_shortcuts(shortcuts: dict):
    """Save custom shortcuts to settings.json."""
    data = {"shortcuts": shortcuts}
    with open(SETTINGS_PATH, "w") as f:
        json.dump(data, f, indent=2)
