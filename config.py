import os
import json
from PyQt6.QtGui import QColor

# --- Brand Colors ---
COLOR_MORADO = QColor(139, 92, 246)      # #8B5CF6
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
STROKE_HIGHLIGHTER = 20.0
DEFAULT_STROKE = STROKE_MEDIUM
STROKE_STEPS = [STROKE_THIN, STROKE_MEDIUM, STROKE_THICK]

# --- Fade ---
FADE_DELAY = 3.0        # seconds before fade starts
FADE_DURATION = 0.5      # seconds for fade animation
CANVAS_FPS = 60          # repaint rate

# --- Laser (ambar, refined — subtle & elegant) ---
LASER_DOT_RADIUS = 5.0
LASER_GLOW_RADIUS = 14.0
LASER_TRAIL_LENGTH = 18  # short, clean trail
LASER_COLOR = COLOR_AMBAR  # ambar pointer

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
LOGO_PATH = os.path.join(os.path.dirname(__file__), "logo_small.png")
LOGO_SIZE = 22

# --- Ripple (click effect on laser) ---
RIPPLE_MAX_RADIUS = 18.0
RIPPLE_DURATION = 0.4  # seconds

# --- Highlighter ---
HIGHLIGHTER_OPACITY = 0.35

# --- Settings persistence ---
SETTINGS_PATH = os.path.join(os.path.dirname(__file__), "settings.json")


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
