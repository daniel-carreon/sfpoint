"""Per-screen transparent overlays with shared annotation state.

Architecture: CanvasManager (QObject) owns all state and creates one
ScreenOverlay (QWidget) per physical monitor.  Coordinates are stored
in GLOBAL screen space; each overlay translates its QPainter so that
global coords map to local widget pixels.  This guarantees that every
monitor receives its own native macOS NSWindow and mouse‐event routing.
"""

import ctypes
import ctypes.util
import time
from ctypes import c_void_p
import AppKit
import objc
from pynput import mouse as pynput_mouse
from PyQt6.QtWidgets import QWidget, QApplication
from PyQt6.QtCore import Qt, QTimer, QPointF, QObject, pyqtSignal, QPoint, QRectF
from PyQt6.QtGui import QPainter, QColor, QCursor, QFont
from core.drawing import Annotation, ShapeRenderer
from config import (
    CANVAS_FPS, FADE_DELAY, FADE_DURATION,
    TOOL_LASER, TOOL_TEXT, TOOL_FREEHAND, TOOL_HIGHLIGHTER,
    LASER_TRAIL_LENGTH, DEFAULT_TOOL, DEFAULT_STROKE,
    COLOR_PALETTE, DEFAULT_COLOR_INDEX, STROKE_HIGHLIGHTER,
    TEXT_FONT_SIZE, RIPPLE_DURATION,
)

# --- Core Graphics cursor control (system-wide) ---
_cg_path = ctypes.util.find_library("CoreGraphics")
if not _cg_path:
    _cg_path = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
_cg = ctypes.cdll.LoadLibrary(_cg_path)
_cg.CGMainDisplayID.argtypes = []
_cg.CGMainDisplayID.restype = ctypes.c_uint32
_cg.CGDisplayHideCursor.argtypes = [ctypes.c_uint32]
_cg.CGDisplayHideCursor.restype = ctypes.c_int32
_cg.CGDisplayShowCursor.argtypes = [ctypes.c_uint32]
_cg.CGDisplayShowCursor.restype = ctypes.c_int32
_CG_DISPLAY = _cg.CGMainDisplayID()


def _cg_hide_cursor():
    _cg.CGDisplayHideCursor(_CG_DISPLAY)


def _cg_show_cursor():
    _cg.CGDisplayShowCursor(_CG_DISPLAY)


# ─────────────────────────────────────────────────────────────────────
# ScreenOverlay — one transparent fullscreen widget per physical screen
# ─────────────────────────────────────────────────────────────────────

class ScreenOverlay(QWidget):
    """Transparent click‐through overlay covering exactly one screen."""

    def __init__(self, screen, manager: "CanvasManager"):
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
        self.setGeometry(screen.geometry())

    # --- native macOS helpers ---

    def showEvent(self, event):
        super().showEvent(event)
        try:
            self._setup_native_macos()
        except Exception as e:
            print(f"Warning: native macOS setup failed on {self._screen.name()}: {e}")
        self._set_ignores_mouse(True)

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

    def _set_ignores_mouse(self, ignore: bool):
        try:
            ns_view = objc.objc_object(c_void_p=c_void_p(self.winId().__int__()))
            ns_view.window().setIgnoresMouseEvents_(ignore)
        except Exception:
            pass

    def _bring_to_front(self):
        try:
            ns_view = objc.objc_object(c_void_p=c_void_p(self.winId().__int__()))
            ns_view.window().orderFrontRegardless()
        except Exception:
            pass

    def _grab_focus(self):
        self.setWindowFlag(Qt.WindowType.WindowDoesNotAcceptFocus, False)
        self.show()
        self.activateWindow()
        self.setFocus(Qt.FocusReason.OtherFocusReason)

    def _release_focus(self):
        self.setWindowFlag(Qt.WindowType.WindowDoesNotAcceptFocus, True)
        self.show()
        ignore = not self._mgr._active or self._mgr._tool == TOOL_LASER
        self._set_ignores_mouse(ignore)

    # --- event forwarding (local → global → manager) ---

    def _to_global(self, local_pos) -> tuple:
        g = self.mapToGlobal(QPoint(int(local_pos.x()), int(local_pos.y())))
        return (g.x(), g.y())

    def mousePressEvent(self, event):
        if event.button() == Qt.MouseButton.RightButton:
            self._mgr.context_menu_requested.emit(event.globalPosition().toPoint())
            event.accept()
            return
        gxy = self._to_global(event.position())
        self._mgr._handle_press(gxy, event.button(), self)
        event.accept()

    def mouseMoveEvent(self, event):
        gxy = self._to_global(event.position())
        self._mgr._handle_move(gxy)
        event.accept()

    def mouseReleaseEvent(self, event):
        self._mgr._handle_release(event.button())
        event.accept()

    def keyPressEvent(self, event):
        self._mgr._handle_key(event, self)

    # --- painting (translate painter so global coords → local pixels) ---

    def paintEvent(self, event):
        mgr = self._mgr
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        geo = self.geometry()
        painter.translate(-geo.x(), -geo.y())

        # Persisted annotations
        for ann in mgr._annotations:
            ShapeRenderer.render(painter, ann)

        # In-progress shape
        if mgr._current:
            ShapeRenderer.render(painter, mgr._current)

        # Laser
        if mgr._laser_active:
            ShapeRenderer.draw_laser(painter, mgr._laser_pos, mgr._laser_trail)

        # Ripples
        now = time.time()
        for ripple in mgr._ripples:
            progress = (now - ripple["start_time"]) / RIPPLE_DURATION
            if 0.0 <= progress < 1.0:
                ShapeRenderer.draw_ripple(painter, ripple["pos"], progress)

        # Text cursor
        if mgr._text_mode and mgr._text_pos:
            color = COLOR_PALETTE[mgr._color_index]
            font = QFont(".AppleSystemUIFont", TEXT_FONT_SIZE)
            font.setBold(True)
            painter.setFont(font)
            fm = painter.fontMetrics()
            text_w = fm.horizontalAdvance(mgr._text_buffer)
            tx, ty = mgr._text_pos

            if mgr._text_buffer:
                painter.setPen(color)
                painter.drawText(QPointF(tx, ty), mgr._text_buffer)

            if mgr._text_cursor_visible:
                cursor_x = tx + text_w + 2
                cursor_y_top = ty - fm.ascent()
                cursor_y_bot = ty + fm.descent()
                painter.setPen(QColor(255, 255, 255, 200))
                painter.drawLine(
                    QPointF(cursor_x, cursor_y_top),
                    QPointF(cursor_x, cursor_y_bot),
                )

        painter.end()


# ─────────────────────────────────────────────────────────────────────
# CanvasManager — owns all state, creates one ScreenOverlay per monitor
# ─────────────────────────────────────────────────────────────────────

class CanvasManager(QObject):
    """Drop-in replacement for the old monolithic CanvasWidget.

    Public API is identical: set_active, set_tool, set_laser, set_color_index,
    set_stroke_width, undo, clear_all, and the same signals/properties.
    """

    tool_changed = pyqtSignal(str)
    color_changed = pyqtSignal(int)
    context_menu_requested = pyqtSignal(object)
    _ripple_signal = pyqtSignal(float, float)

    def __init__(self):
        super().__init__()
        # Drawing state
        self._annotations: list[Annotation] = []
        self._current: Annotation | None = None
        self._drawing = False
        self._active = False

        # Tool state
        self._tool = DEFAULT_TOOL
        self._color_index = DEFAULT_COLOR_INDEX
        self._stroke_width = DEFAULT_STROKE

        # Laser state
        self._laser_active = False
        self._laser_pos: tuple | None = None
        self._laser_trail: list[tuple] = []
        self._mouse_listener: pynput_mouse.Listener | None = None
        self._cursor_hidden = False

        # Ripple state
        self._ripples: list[dict] = []

        # Text input state
        self._text_mode = False
        self._text_buffer = ""
        self._text_pos: tuple | None = None
        self._text_cursor_visible = True
        self._focus_overlay: ScreenOverlay | None = None

        # Per-screen overlays
        self._overlays: list[ScreenOverlay] = []
        self._create_overlays()

        app = QApplication.instance()
        if app:
            app.screenAdded.connect(self._recreate_overlays)
            app.screenRemoved.connect(self._recreate_overlays)

        # Timers
        self._fade_timer = QTimer()
        self._fade_timer.setInterval(1000 // CANVAS_FPS)
        self._fade_timer.timeout.connect(self._tick_fade)
        self._fade_timer.start()

        self._cursor_timer = QTimer()
        self._cursor_timer.setInterval(530)
        self._cursor_timer.timeout.connect(self._blink_cursor)

        self._laser_poll_timer = QTimer()
        self._laser_poll_timer.setInterval(16)
        self._laser_poll_timer.timeout.connect(self._poll_laser_position)

        self._ripple_signal.connect(self._add_ripple, Qt.ConnectionType.QueuedConnection)

    # --- overlay management ---

    def _create_overlays(self):
        for screen in QApplication.screens():
            ov = ScreenOverlay(screen, self)
            self._overlays.append(ov)

    def _recreate_overlays(self, _screen=None):
        for ov in self._overlays:
            ov.close()
        self._overlays.clear()
        self._create_overlays()
        self.show()

    def show(self):
        for ov in self._overlays:
            ov.show()

    def _update_all(self):
        for ov in self._overlays:
            ov.update()

    def _set_all_ignores_mouse(self, ignore: bool):
        for ov in self._overlays:
            ov._set_ignores_mouse(ignore)

    def _bring_all_to_front(self):
        for ov in self._overlays:
            ov._bring_to_front()

    # --- public API (same as old CanvasWidget) ---

    def set_laser(self, on: bool):
        if on == self._laser_active:
            return
        self._laser_active = on
        if on:
            self._bring_all_to_front()
            self._set_all_ignores_mouse(True)
            self._laser_poll_timer.start()
            if not self._mouse_listener:
                self._mouse_listener = pynput_mouse.Listener(
                    on_move=self._on_global_move,
                    on_click=self._on_global_click,
                )
                self._mouse_listener.daemon = True
                self._mouse_listener.start()
            self._cursor_hidden = True
            _cg_hide_cursor()
        else:
            self._cursor_hidden = False
            self._laser_poll_timer.stop()
            self._laser_pos = None
            self._laser_trail.clear()
            if self._mouse_listener:
                self._mouse_listener.stop()
                self._mouse_listener = None
            for _ in range(500):
                _cg_show_cursor()
            if not self._active:
                self._set_all_ignores_mouse(True)
        self._update_all()

    def set_active(self, active: bool):
        if active == self._active:
            return
        self._active = active
        if active:
            self._bring_all_to_front()
            self._set_all_ignores_mouse(False)
            cursor = Qt.CursorShape.IBeamCursor if self._tool == TOOL_TEXT else Qt.CursorShape.CrossCursor
            for ov in self._overlays:
                ov.setCursor(cursor)
        else:
            for ov in self._overlays:
                ov.unsetCursor()
            self._finish_current()
            if self._text_mode:
                self._commit_text()
            self._set_all_ignores_mouse(True)

    def set_tool(self, tool: str):
        self._tool = tool
        if self._active:
            self._set_all_ignores_mouse(False)
            cursor = Qt.CursorShape.IBeamCursor if tool == TOOL_TEXT else Qt.CursorShape.CrossCursor
            for ov in self._overlays:
                ov.setCursor(cursor)

    def set_color_index(self, idx: int):
        if 0 <= idx < len(COLOR_PALETTE):
            self._color_index = idx
            self.color_changed.emit(idx)

    def set_stroke_width(self, width: float):
        self._stroke_width = width

    def undo(self):
        if self._annotations:
            self._annotations.pop()
            self._update_all()

    def clear_all(self):
        self._annotations.clear()
        self._update_all()

    @property
    def current_tool(self) -> str:
        return self._tool

    @property
    def current_color_index(self) -> int:
        return self._color_index

    @property
    def is_active(self) -> bool:
        return self._active

    @property
    def is_laser_active(self) -> bool:
        return self._laser_active

    # --- mouse / keyboard handlers (called by overlays with GLOBAL coords) ---

    def _handle_press(self, gxy: tuple, button, overlay: ScreenOverlay):
        if button != Qt.MouseButton.LeftButton or not self._active:
            return

        if self._tool == TOOL_TEXT:
            if self._text_mode:
                self._commit_text()
            self._text_mode = True
            self._text_pos = gxy
            self._text_buffer = ""
            self._text_cursor_visible = True
            self._cursor_timer.start()
            self._focus_overlay = overlay
            overlay._grab_focus()
            self._update_all()
            return

        if self._tool == TOOL_LASER:
            return

        stroke = STROKE_HIGHLIGHTER if self._tool == TOOL_HIGHLIGHTER else self._stroke_width
        self._current = Annotation(
            tool=self._tool,
            points=[gxy],
            color=QColor(COLOR_PALETTE[self._color_index]),
            stroke_width=stroke,
        )
        self._drawing = True

    def _handle_move(self, gxy: tuple):
        if not self._active or self._tool == TOOL_LASER:
            return
        if self._drawing and self._current:
            if self._tool in (TOOL_FREEHAND, TOOL_HIGHLIGHTER):
                self._current.points.append(gxy)
            else:
                if len(self._current.points) == 1:
                    self._current.points.append(gxy)
                else:
                    self._current.points[-1] = gxy
            self._update_all()

    def _handle_release(self, button):
        if not self._active or button != Qt.MouseButton.LeftButton:
            return
        if self._tool in (TOOL_LASER, TOOL_TEXT):
            return
        self._finish_current()
        self._update_all()

    def _handle_key(self, event, overlay: ScreenOverlay):
        if not self._text_mode:
            return
        key = event.key()
        text = event.text()

        if key in (Qt.Key.Key_Return, Qt.Key.Key_Enter):
            self._commit_text()
        elif key == Qt.Key.Key_Escape:
            self._text_mode = False
            self._text_buffer = ""
            self._text_pos = None
            self._cursor_timer.stop()
            if self._focus_overlay:
                self._focus_overlay._release_focus()
                self._focus_overlay = None
            self._update_all()
        elif key == Qt.Key.Key_Backspace:
            self._text_buffer = self._text_buffer[:-1]
            self._update_all()
        elif text and text.isprintable():
            self._text_buffer += text
            self._update_all()

    # --- internal helpers ---

    def _finish_current(self):
        if self._current and len(self._current.points) >= 2:
            self._annotations.append(self._current)
        self._current = None
        self._drawing = False

    def _commit_text(self):
        if self._text_buffer and self._text_pos:
            ann = Annotation(
                tool="text",
                points=[self._text_pos],
                color=QColor(COLOR_PALETTE[self._color_index]),
                stroke_width=self._stroke_width,
                text=self._text_buffer,
            )
            self._annotations.append(ann)
        self._text_mode = False
        self._text_buffer = ""
        self._text_pos = None
        self._cursor_timer.stop()
        if self._focus_overlay:
            self._focus_overlay._release_focus()
            self._focus_overlay = None
        self._update_all()

    def _blink_cursor(self):
        self._text_cursor_visible = not self._text_cursor_visible
        self._update_all()

    # --- laser polling (global coords) ---

    def _poll_laser_position(self):
        if self._cursor_hidden:
            _cg_hide_cursor()

        pos = QCursor.pos()
        xy = (pos.x(), pos.y())

        if self._laser_pos != xy:
            self._laser_pos = xy
            self._laser_trail.append(xy)
            if len(self._laser_trail) > LASER_TRAIL_LENGTH:
                self._laser_trail = self._laser_trail[-LASER_TRAIL_LENGTH:]
        else:
            if self._laser_trail:
                self._laser_trail.pop(0)

        self._update_all()

    def _on_global_move(self, x: int, y: int):
        try:
            if self._cursor_hidden:
                _cg.CGDisplayHideCursor(_CG_DISPLAY)
        except Exception:
            pass

    def _on_global_click(self, x: int, y: int, button, pressed: bool):
        try:
            if self._cursor_hidden:
                _cg.CGDisplayHideCursor(_CG_DISPLAY)
            if pressed:
                self._ripple_signal.emit(float(x), float(y))
        except Exception:
            pass

    def _add_ripple(self, x: float, y: float):
        self._ripples.append({"pos": (x, y), "start_time": time.time()})

    # --- fade ---

    def _tick_fade(self):
        now = time.time()
        changed = False
        to_remove = []

        for i, ann in enumerate(self._annotations):
            age = now - ann.created_at
            if age > FADE_DELAY:
                fade_progress = (age - FADE_DELAY) / FADE_DURATION
                ann.opacity = max(0.0, 1.0 - fade_progress)
                changed = True
                if ann.opacity <= 0:
                    to_remove.append(i)

        if to_remove:
            for i in reversed(to_remove):
                self._annotations.pop(i)
            changed = True

        if self._ripples:
            self._ripples = [r for r in self._ripples if now - r["start_time"] < RIPPLE_DURATION]
            changed = True

        if changed:
            self._update_all()
