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
COLOR_CUSTOM = QColor(14, 165, 233)      # #0EA5E9 sky blue (user-replaceable)

# Ordered palette — indices 0-4 are presets, 5 is custom (mutable)
COLOR_PALETTE = [COLOR_MORADO, COLOR_AMBAR, COLOR_RED, COLOR_GREEN, COLOR_WHITE, COLOR_CUSTOM]
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
    "p": TOOL_LASER,
    "i": TOOL_HIGHLIGHTER,
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
IDLE_HIDE_MS = 500       # ms after deactivation before overlays hide from screenshot picker
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


def _read_settings() -> dict:
    if os.path.exists(SETTINGS_PATH):
        try:
            with open(SETTINGS_PATH) as f:
                return json.load(f)
        except Exception:
            pass
    return {}


def _write_settings(data: dict):
    os.makedirs(os.path.dirname(SETTINGS_PATH), exist_ok=True)
    with open(SETTINGS_PATH, "w") as f:
        json.dump(data, f, indent=2)


def load_shortcuts() -> dict:
    saved = _read_settings().get("shortcuts", {})
    # Drop any non-ASCII keys left over from the old Option-modifier era (e.g. "å")
    saved = {k: v for k, v in saved.items() if k.isascii() and k.isalpha()}
    merged = dict(TOOL_SHORTCUTS)
    merged.update(saved)
    return merged


def save_shortcuts(shortcuts: dict):
    data = _read_settings()
    data["shortcuts"] = shortcuts
    _write_settings(data)


def load_prefs() -> dict:
    """Load persistent UI prefs: color_index, stroke_width, arrow_tip_first, custom_color."""
    data = _read_settings().get("prefs", {})
    return {
        "color_index": data.get("color_index", DEFAULT_COLOR_INDEX),
        "stroke_width": data.get("stroke_width", DEFAULT_STROKE),
        "arrow_tip_first": data.get("arrow_tip_first", False),
        "custom_color": data.get("custom_color", None),  # hex string or None
    }


def save_prefs(color_index: int, stroke_width: float, arrow_tip_first: bool, custom_color_hex: str | None):
    data = _read_settings()
    data["prefs"] = {
        "color_index": color_index,
        "stroke_width": stroke_width,
        "arrow_tip_first": arrow_tip_first,
        "custom_color": custom_color_hex,
    }
    _write_settings(data)
