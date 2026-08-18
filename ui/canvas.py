"""Transparent click-through overlays that draw the laser.

One overlay per physical screen. Coordinates live in GLOBAL screen space and
each overlay translates its painter, so the laser and its trail cross monitors
without seams.

Efficiency contract:
  - laser OFF  → overlays hidden, zero timers, zero listeners, ~0% CPU
  - laser ON   → one 60fps timer, repainting ONLY the dirty rect (never the
                 full screen)
"""

import ctypes
import ctypes.util
import time
from ctypes import c_void_p

import AppKit
import objc
from pynput import mouse as pynput_mouse
from PyQt6.QtWidgets import QWidget, QApplication
from PyQt6.QtCore import Qt, QTimer, QObject, pyqtSignal, QRectF
from PyQt6.QtGui import QPainter, QCursor

from core.laser import draw_laser, draw_ripple, opposite_color, LASER_PAD, RIPPLE_PAD
from config import (
    CANVAS_FPS, LASER_TRAIL_LENGTH, RIPPLE_DURATION,
    LASER_OFF, LASER_COLORS,
)

# --- Core Graphics cursor control ---
_cg_path = ctypes.util.find_library("CoreGraphics") or \
    "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
_cg = ctypes.cdll.LoadLibrary(_cg_path)
_cg.CGMainDisplayID.argtypes = []
_cg.CGMainDisplayID.restype = ctypes.c_uint32
_cg.CGDisplayHideCursor.argtypes = [ctypes.c_uint32]
_cg.CGDisplayHideCursor.restype = ctypes.c_int32
_cg.CGDisplayShowCursor.argtypes = [ctypes.c_uint32]
_cg.CGDisplayShowCursor.restype = ctypes.c_int32
_CG_DISPLAY = _cg.CGMainDisplayID()


class LaserOverlay(QWidget):
    """Transparent, always click-through overlay covering exactly one screen."""

    def __init__(self, screen, manager: "LaserCanvas"):
        super().__init__()
        self._screen = screen
        self._mgr = manager

        self.setWindowFlags(
            Qt.WindowType.FramelessWindowHint
            | Qt.WindowType.WindowStaysOnTopHint
            | Qt.WindowType.Tool
            | Qt.WindowType.WindowDoesNotAcceptFocus
        )
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setAttribute(Qt.WidgetAttribute.WA_ShowWithoutActivating)
        self.setAttribute(Qt.WidgetAttribute.WA_TransparentForMouseEvents)
        self.setGeometry(screen.geometry())

    # --- native macOS ---

    def showEvent(self, event):
        super().showEvent(event)
        try:
            self._setup_native_macos()
        except Exception as e:
            print(f"Warning: native setup failed on {self._screen.name()}: {e}")

    def _setup_native_macos(self):
        ns_view = objc.objc_object(c_void_p=c_void_p(self.winId().__int__()))
        ns_window = ns_view.window()
        ns_window.setLevel_(AppKit.NSFloatingWindowLevel + 1)
        ns_window.setStyleMask_(
            ns_window.styleMask() | AppKit.NSWindowStyleMaskNonactivatingPanel
        )
        ns_window.setHidesOnDeactivate_(False)
        ns_window.setCollectionBehavior_(
            AppKit.NSWindowCollectionBehaviorCanJoinAllSpaces
            | AppKit.NSWindowCollectionBehaviorStationary
            | AppKit.NSWindowCollectionBehaviorFullScreenAuxiliary
        )
        ns_window.setBackgroundColor_(AppKit.NSColor.clearColor())
        ns_window.setOpaque_(False)
        ns_window.setHasShadow_(False)
        # Clicks ALWAYS pass through. The laser never blocks the mouse.
        ns_window.setIgnoresMouseEvents_(True)

    def bring_to_front(self):
        try:
            ns_view = objc.objc_object(c_void_p=c_void_p(self.winId().__int__()))
            ns_view.window().orderFrontRegardless()
        except Exception:
            pass

    # --- painting (global coords → local pixels) ---

    def paintEvent(self, _event):
        mgr = self._mgr
        if mgr.state == LASER_OFF:
            return

        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        geo = self.geometry()
        painter.translate(-geo.x(), -geo.y())

        draw_laser(painter, mgr.pos, mgr.trail, mgr.color)

        now = time.time()
        for ripple in mgr.ripples:
            progress = (now - ripple["t0"]) / RIPPLE_DURATION
            if 0.0 <= progress < 1.0:
                draw_ripple(painter, ripple["pos"], progress, ripple["color"])

        painter.end()


class LaserCanvas(QObject):
    """Owns laser state and drives the overlays."""

    _ripple_signal = pyqtSignal(float, float)

    def __init__(self):
        super().__init__()
        self.state = LASER_OFF
        self.color = LASER_COLORS[1]
        self.pos: tuple | None = None
        self.trail: list[tuple] = []
        self.ripples: list[dict] = []

        self._prev_dirty: QRectF | None = None
        self._mouse_listener: pynput_mouse.Listener | None = None
        self._cursor_hides = 0

        self._overlays: list[LaserOverlay] = []
        self._build_overlays()

        app = QApplication.instance()
        if app:
            app.screenAdded.connect(self._rebuild_overlays)
            app.screenRemoved.connect(self._rebuild_overlays)

        self._timer = QTimer()
        self._timer.setInterval(1000 // CANVAS_FPS)
        self._timer.timeout.connect(self._tick)

        self._ripple_signal.connect(self._add_ripple, Qt.ConnectionType.QueuedConnection)

    # --- overlays ---

    def _build_overlays(self):
        for screen in QApplication.screens():
            self._overlays.append(LaserOverlay(screen, self))

    def _rebuild_overlays(self, _screen=None):
        was_on = self.state != LASER_OFF
        for ov in self._overlays:
            ov.close()
        self._overlays.clear()
        self._build_overlays()
        if was_on:
            self._show_overlays()

    def _show_overlays(self):
        for ov in self._overlays:
            ov.show()
            ov.bring_to_front()

    def _hide_overlays(self):
        for ov in self._overlays:
            ov.hide()

    # --- public API ---

    def set_state(self, state: int):
        """0 = off, 1 = ambar, 2 = morado."""
        if state == self.state:
            return
        self.state = state

        if state == LASER_OFF:
            self._timer.stop()
            self._stop_mouse_listener()
            self._restore_cursor()
            self.pos = None
            self.trail.clear()
            self.ripples.clear()
            self._prev_dirty = None
            self._hide_overlays()
            return

        self.color = LASER_COLORS[state]
        self.trail.clear()
        self.pos = None
        self._show_overlays()
        self._start_mouse_listener()
        self._hide_cursor()
        self._timer.start()
        self._tick()

    # --- frame tick ---

    def _tick(self):
        # The window server re-shows the cursor whenever focus moves, so we
        # keep re-hiding it and count every hide to undo them EXACTLY later.
        self._hide_cursor()

        p = QCursor.pos()
        xy = (p.x(), p.y())
        if xy != self.pos:
            self.pos = xy
            self.trail.append(xy)
            if len(self.trail) > LASER_TRAIL_LENGTH:
                del self.trail[:-LASER_TRAIL_LENGTH]
        elif self.trail:
            # Cursor stopped — let the trail decay into the dot
            self.trail.pop(0)

        if self.ripples:
            now = time.time()
            self.ripples = [r for r in self.ripples if now - r["t0"] < RIPPLE_DURATION]

        self._repaint_dirty()

    def _repaint_dirty(self):
        current = self._dirty_global()
        if current is None and self._prev_dirty is None:
            return
        if current is None:
            region = self._prev_dirty
        elif self._prev_dirty is None:
            region = current
        else:
            region = current.united(self._prev_dirty)
        self._prev_dirty = current

        for ov in self._overlays:
            if not ov.isVisible():
                continue
            geo = ov.geometry()
            local = region.translated(-geo.x(), -geo.y()).toAlignedRect()
            ov.update(local.adjusted(-2, -2, 2, 2))

    def _dirty_global(self) -> QRectF | None:
        rect = None
        points = list(self.trail)
        if self.pos:
            points.append(self.pos)
        if points:
            xs = [p[0] for p in points]
            ys = [p[1] for p in points]
            rect = QRectF(
                min(xs) - LASER_PAD, min(ys) - LASER_PAD,
                (max(xs) - min(xs)) + LASER_PAD * 2,
                (max(ys) - min(ys)) + LASER_PAD * 2,
            )
        for r in self.ripples:
            x, y = r["pos"]
            rr = QRectF(x - RIPPLE_PAD, y - RIPPLE_PAD, RIPPLE_PAD * 2, RIPPLE_PAD * 2)
            rect = rr if rect is None else rect.united(rr)
        return rect

    # --- click ripples (needs Input Monitoring; laser works without it) ---

    def _start_mouse_listener(self):
        if self._mouse_listener:
            return
        try:
            self._mouse_listener = pynput_mouse.Listener(on_click=self._on_global_click)
            self._mouse_listener.daemon = True
            self._mouse_listener.start()
        except Exception:
            self._mouse_listener = None

    def _stop_mouse_listener(self):
        if self._mouse_listener:
            try:
                self._mouse_listener.stop()
            except Exception:
                pass
            self._mouse_listener = None

    def _on_global_click(self, x, y, button, pressed):
        if pressed:
            self._ripple_signal.emit(float(x), float(y))

    def _add_ripple(self, x: float, y: float):
        if self.state == LASER_OFF:
            return
        self.ripples.append({
            "pos": (x, y),
            "t0": time.time(),
            "color": opposite_color(self.color),
        })

    # --- cursor (balanced hide/show — an unbalanced count leaves the user
    #     with an invisible cursor system-wide, which is unrecoverable) ---

    def _hide_cursor(self):
        _cg.CGDisplayHideCursor(_CG_DISPLAY)
        self._cursor_hides += 1

    def _restore_cursor(self):
        for _ in range(self._cursor_hides + 8):
            _cg.CGDisplayShowCursor(_CG_DISPLAY)
        self._cursor_hides = 0

    # --- shutdown ---

    def shutdown(self):
        """Always call before quitting: an app that dies with the cursor hidden
        takes the user's cursor with it."""
        self._timer.stop()
        self._stop_mouse_listener()
        self._restore_cursor()
