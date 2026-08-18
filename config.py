"""SFPoint configuration — laser pointer only.

One hotkey (Option+P) cycles: off → ambar → morado → off.
Nothing else. No tools, no shapes, no settings file.
"""

import os
import sys
from PyQt6.QtGui import QColor

# --- Bundle vs dev mode ---
IS_BUNDLE = getattr(sys, "frozen", False)
_ASSETS_DIR = sys._MEIPASS if IS_BUNDLE else os.path.dirname(__file__)

# --- Brand colors ---
COLOR_AMBAR = QColor(245, 158, 11)    # #F59E0B
COLOR_MORADO = QColor(140, 39, 241)   # #8C27F1

# --- Laser states (Option+P cycles through these) ---
LASER_OFF = 0
LASER_AMBAR = 1
LASER_MORADO = 2

LASER_COLORS = {LASER_AMBAR: COLOR_AMBAR, LASER_MORADO: COLOR_MORADO}
LASER_LABELS = {LASER_OFF: "Apagado", LASER_AMBAR: "Ambar", LASER_MORADO: "Morado"}

# --- Laser geometry ---
LASER_DOT_RADIUS = 7.5
LASER_GLOW_RADIUS = 21.0
LASER_TRAIL_LENGTH = 18   # points kept in the fading trail

# --- Ripple (click shockwave, drawn in the opposite color) ---
RIPPLE_MAX_RADIUS = 20.0
RIPPLE_DURATION = 0.55    # seconds

# --- Render ---
CANVAS_FPS = 60           # only ticks while the laser is ON

# --- Hotkey ---
SHORTCUT_LASER = "p"      # Option+P
VK_P = 35                 # macOS virtual key code for "p"

# --- Assets ---
LOGO_PATH = os.path.join(_ASSETS_DIR, "logo_small.png")
LOGO_SIZE = 22

# --- App identity ---
BUNDLE_ID = "so.saasfactory.sfpoint"
APP_PATH = "/Applications/SFPoint.app"
