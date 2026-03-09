"""Fullscreen transparent overlay with click-through toggle."""

import ctypes
import ctypes.util
import time
from ctypes import c_void_p
import AppKit
import objc
from pynput import mouse as pynput_mouse
from PyQt6.QtWidgets import QWidget, QApplication
from PyQt6.QtCore import Qt, QTimer, QPointF, pyqtSignal
from PyQt6.QtGui import QPainter, QColor, QCursor
from core.drawing import Annotation, ShapeRenderer
from config import (
    CANVAS_FPS, FADE_DELAY, FADE_DURATION,
    TOOL_LASER, TOOL_TEXT, TOOL_FREEHAND, TOOL_HIGHLIGHTER,
    LASER_TRAIL_LENGTH, DEFAULT_TOOL, DEFAULT_STROKE,
    COLOR_PALETTE, DEFAULT_COLOR_INDEX, STROKE_HIGHLIGHTER,
    TEXT_FONT_SIZE, RIPPLE_DURATION,
)

# --- Core Graphics cursor control (system-wide, not per-app like NSCursor) ---
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
    """Hide cursor at Core Graphics level — system-wide, survives app switches."""
    _cg.CGDisplayHideCursor(_CG_DISPLAY)


def _cg_show_cursor():
    """Show cursor at Core Graphics level."""
    _cg.CGDisplayShowCursor(_CG_DISPLAY)


class CanvasWidget(QWidget):
    """Fullscreen transparent overlay. Click-through when inactive, captures mouse when drawing."""

    tool_changed = pyqtSignal(str)
    color_changed = pyqtSignal(int)
    context_menu_requested = pyqtSignal(object)  # global QPoint
    _ripple_signal = pyqtSignal(float, float)  # thread-safe ripple trigger

    def __init__(self):
        super().__init__()
        self._annotations: list[Annotation] = []
        self._current: Annotation | None = None
        self._drawing = False
        self._active = False

        # Tool state
        self._tool = DEFAULT_TOOL
        self._color_index = DEFAULT_COLOR_INDEX
        self._stroke_width = DEFAULT_STROKE

        # Laser state (independent layer)
        self._laser_active = False
        self._laser_pos: tuple | None = None
        self._laser_trail: list[tuple] = []
        self._mouse_listener: pynput_mouse.Listener | None = None
        self._cursor_hidden = False  # tracks if we're actively hiding

        # Ripple state (morado expanding ring on click)
        self._ripples: list[dict] = []  # [{pos, start_time}]

        # Laser cursor polling timer
        self._laser_poll_timer = QTimer()
        self._laser_poll_timer.setInterval(16)  # ~60fps
        self._laser_poll_timer.timeout.connect(self._poll_laser_position)

        # Text input state
        self._text_mode = False
        self._text_buffer = ""
        self._text_pos: tuple | None = None
        self._text_cursor_visible = True

        # Window setup
        self.setWindowFlags(
            Qt.WindowType.FramelessWindowHint
            | Qt.WindowType.WindowStaysOnTopHint
            | Qt.WindowType.Tool
            | Qt.WindowType.WindowDoesNotAcceptFocus
        )
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setAttribute(Qt.WidgetAttribute.WA_ShowWithoutActivating)

        # Cover ALL screens (virtual desktop bounding rect)
        self._update_geometry()
        # Re-cover if monitors added/removed
        app = QApplication.instance()
        if app:
            app.screenAdded.connect(self._update_geometry)
            app.screenRemoved.connect(self._update_geometry)

    def _update_geometry(self, _screen=None):
        # Build explicit union of ALL screen geometries (more reliable than virtualGeometry)
        screens = QApplication.screens()
        if screens:
            from PyQt6.QtCore import QRect
            union = screens[0].geometry()
            for s in screens[1:]:
                union = union.united(s.geometry())
            self.setGeometry(union)

        # Only create timers once (avoid duplication on screen add/remove)
        if not hasattr(self, "_fade_timer"):
            self._fade_timer = QTimer()
            self._fade_timer.setInterval(1000 // CANVAS_FPS)
            self._fade_timer.timeout.connect(self._tick_fade)
            self._fade_timer.start()

            self._cursor_timer = QTimer()
            self._cursor_timer.setInterval(530)
            self._cursor_timer.timeout.connect(self._blink_cursor)

            self._ripple_signal.connect(self._add_ripple, Qt.ConnectionType.QueuedConnection)

    def _grab_focus(self):
        """Temporarily allow focus for text input."""
        self.setWindowFlag(Qt.WindowType.WindowDoesNotAcceptFocus, False)
        self.show()  # re-apply flags
        self.activateWindow()
        self.setFocus(Qt.FocusReason.OtherFocusReason)

    def _release_focus(self):
        """Restore no-focus behavior after text input."""
        self.setWindowFlag(Qt.WindowType.WindowDoesNotAcceptFocus, True)
        self.show()  # re-apply flags
        self._set_ignores_mouse(not self._active or self._tool == TOOL_LASER)

    def _blink_cursor(self):
        self._text_cursor_visible = not self._text_cursor_visible
        self.update()

    def showEvent(self, event):
        super().showEvent(event)
        try:
            self._setup_native_macos()
        except Exception as e:
            print(f"Warning: native macOS setup failed: {e}")
        # Start in click-through mode
        self._set_ignores_mouse(True)
        # Re-apply geometry AFTER native setup to ensure multi-monitor coverage
        self._update_geometry()

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

        # Build NSRect covering ALL physical screens (critical for multi-monitor)
        all_screens = AppKit.NSScreen.screens()
        if all_screens:
            union = all_screens[0].frame()
            for s in all_screens[1:]:
                union = AppKit.NSUnionRect(union, s.frame())
            ns_window.setFrame_display_(union, True)

    def _set_ignores_mouse(self, ignore: bool):
        try:
            ns_view = objc.objc_object(c_void_p=c_void_p(self.winId().__int__()))
            ns_window = ns_view.window()
            ns_window.setIgnoresMouseEvents_(ignore)
        except Exception:
            pass

    def _bring_to_front(self):
        try:
            ns_view = objc.objc_object(c_void_p=c_void_p(self.winId().__int__()))
            ns_window = ns_view.window()
            ns_window.orderFrontRegardless()
        except Exception:
            pass

    # --- Laser: click-through with cursor polling ---

    def _start_laser_mode(self):
        """Start laser: click-through + cursor polling + mouse listener for ripples."""
        self._set_ignores_mouse(True)
        self._laser_poll_timer.start()
        # pynput mouse listener: on_move hides cursor IN the CGEventTap pipeline
        # (before macOS window server can show it), on_click for ripple + re-hide
        if not self._mouse_listener:
            self._mouse_listener = pynput_mouse.Listener(
                on_move=self._on_global_move,
                on_click=self._on_global_click,
            )
            self._mouse_listener.daemon = True
            self._mouse_listener.start()

    def _stop_laser_mode(self):
        """Stop laser polling and mouse listener."""
        self._laser_poll_timer.stop()
        self._laser_pos = None
        self._laser_trail.clear()
        if self._mouse_listener:
            self._mouse_listener.stop()
            self._mouse_listener = None

    def _poll_laser_position(self):
        """Poll QCursor.pos() for laser dot — no mouse capture needed."""
        # Backstop: re-hide every 16ms in case click/app-switch showed cursor
        if self._cursor_hidden:
            _cg_hide_cursor()

        global_pos = QCursor.pos()
        local_pos = self.mapFromGlobal(global_pos)
        xy = (local_pos.x(), local_pos.y())

        if self._laser_pos != xy:
            self._laser_pos = xy
            self._laser_trail.append(xy)
            if len(self._laser_trail) > LASER_TRAIL_LENGTH:
                self._laser_trail = self._laser_trail[-LASER_TRAIL_LENGTH:]
        else:
            # Mouse not moving — decay trail
            if self._laser_trail:
                self._laser_trail.pop(0)

        self.update()

    def _on_global_move(self, x: int, y: int):
        """pynput callback — re-hide cursor on every move via CGEventTap."""
        try:
            if self._cursor_hidden:
                _cg.CGDisplayHideCursor(_CG_DISPLAY)
        except Exception:
            pass

    def _on_global_click(self, x: int, y: int, button: pynput_mouse.Button, pressed: bool):
        """pynput callback — fires on any global click while laser is active."""
        try:
            if self._cursor_hidden:
                _cg.CGDisplayHideCursor(_CG_DISPLAY)
            if pressed:
                self._ripple_signal.emit(float(x), float(y))
        except Exception:
            pass

    def _add_ripple(self, x: float, y: float):
        """Add a morado ripple at click position (called on main thread via signal).

        x, y are global screen coords from pynput — convert to local widget coords.
        """
        from PyQt6.QtCore import QPoint
        local = self.mapFromGlobal(QPoint(int(x), int(y)))
        self._ripples.append({"pos": (local.x(), local.y()), "start_time": time.time()})

    # --- Public API ---

    def set_laser(self, on: bool):
        """Toggle laser independently from drawing tools."""
        if on == self._laser_active:
            return
        self._laser_active = on
        if on:
            self._bring_to_front()
            self._start_laser_mode()
            self._cursor_hidden = True
            _cg_hide_cursor()
        else:
            self._cursor_hidden = False
            self._stop_laser_mode()
            # Brute-force show: CG hide/show is ref-counted, so call show
            # enough times to guarantee the counter reaches 0
            for _ in range(500):
                _cg_show_cursor()
            # If no drawing tool active, restore click-through
            if not self._active:
                self._set_ignores_mouse(True)
        self.update()

    def set_active(self, active: bool):
        """Toggle drawing mode on/off."""
        if active == self._active:
            return
        self._active = active

        if active:
            self._bring_to_front()
            self._set_ignores_mouse(False)
            if self._tool == TOOL_TEXT:
                self.setCursor(Qt.CursorShape.IBeamCursor)
            else:
                self.setCursor(Qt.CursorShape.CrossCursor)
        else:
            self.unsetCursor()
            self._finish_current()
            if self._text_mode:
                self._commit_text()
            self._set_ignores_mouse(True)  # always click-through when no drawing tool

    def set_tool(self, tool: str):
        self._tool = tool
        if self._active:
            self._set_ignores_mouse(False)
            if tool == TOOL_TEXT:
                self.setCursor(Qt.CursorShape.IBeamCursor)
            else:
                self.setCursor(Qt.CursorShape.CrossCursor)

    def set_color_index(self, idx: int):
        if 0 <= idx < len(COLOR_PALETTE):
            self._color_index = idx
            self.color_changed.emit(idx)

    def set_stroke_width(self, width: float):
        self._stroke_width = width

    def undo(self):
        if self._annotations:
            self._annotations.pop()
            self.update()

    def clear_all(self):
        self._annotations.clear()
        self.update()

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

    # --- Drawing ---

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
        self._release_focus()
        self.update()

    def mousePressEvent(self, event):
        # Right-click opens context menu anywhere on screen
        if event.button() == Qt.MouseButton.RightButton:
            self.context_menu_requested.emit(event.globalPosition().toPoint())
            event.accept()
            return
        if not self._active or event.button() != Qt.MouseButton.LeftButton:
            return
        pos = event.position()
        xy = (pos.x(), pos.y())

        if self._tool == TOOL_TEXT:
            if self._text_mode:
                self._commit_text()
            self._text_mode = True
            self._text_pos = xy
            self._text_buffer = ""
            self._text_cursor_visible = True
            self._cursor_timer.start()
            self._grab_focus()
            self.update()
            return

        if self._tool == TOOL_LASER:
            return

        stroke = STROKE_HIGHLIGHTER if self._tool == TOOL_HIGHLIGHTER else self._stroke_width
        self._current = Annotation(
            tool=self._tool,
            points=[xy],
            color=QColor(COLOR_PALETTE[self._color_index]),
            stroke_width=stroke,
        )
        self._drawing = True
        event.accept()

    def mouseMoveEvent(self, event):
        if not self._active:
            return
        pos = event.position()
        xy = (pos.x(), pos.y())

        if self._tool == TOOL_LASER:
            return  # Handled by polling timer

        if self._drawing and self._current:
            if self._tool in (TOOL_FREEHAND, TOOL_HIGHLIGHTER):
                self._current.points.append(xy)
            else:
                # For arrow/rect/circle — only keep start + current end
                if len(self._current.points) == 1:
                    self._current.points.append(xy)
                else:
                    self._current.points[-1] = xy
            self.update()

    def mouseReleaseEvent(self, event):
        if not self._active or event.button() != Qt.MouseButton.LeftButton:
            return
        if self._tool == TOOL_LASER:
            return
        if self._tool == TOOL_TEXT:
            return
        self._finish_current()
        self.update()

    def keyPressEvent(self, event):
        if not self._text_mode:
            return
        key = event.key()
        text = event.text()

        if key == Qt.Key.Key_Return or key == Qt.Key.Key_Enter:
            self._commit_text()
        elif key == Qt.Key.Key_Escape:
            self._text_mode = False
            self._text_buffer = ""
            self._text_pos = None
            self._cursor_timer.stop()
            self._release_focus()
            self.update()
        elif key == Qt.Key.Key_Backspace:
            self._text_buffer = self._text_buffer[:-1]
            self.update()
        elif text and text.isprintable():
            self._text_buffer += text
            self.update()

    # --- Fade ---

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

        # Animate ripples — remove finished ones
        if self._ripples:
            self._ripples = [r for r in self._ripples if now - r["start_time"] < RIPPLE_DURATION]
            changed = True

        if changed:
            self.update()

    # --- Paint ---

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        # Draw all persisted annotations
        for ann in self._annotations:
            ShapeRenderer.render(painter, ann)

        # Draw current in-progress shape
        if self._current:
            ShapeRenderer.render(painter, self._current)

        # Draw laser (independent layer)
        if self._laser_active:
            ShapeRenderer.draw_laser(painter, self._laser_pos, self._laser_trail)

        # Draw ripples
        now = time.time()
        for ripple in self._ripples:
            progress = (now - ripple["start_time"]) / RIPPLE_DURATION
            if 0.0 <= progress < 1.0:
                ShapeRenderer.draw_ripple(painter, ripple["pos"], progress)

        # Draw text cursor
        if self._text_mode and self._text_pos:
            from PyQt6.QtGui import QFont
            color = COLOR_PALETTE[self._color_index]
            font = QFont(".AppleSystemUIFont", TEXT_FONT_SIZE)
            font.setBold(True)
            painter.setFont(font)

            # Measure text width for cursor position
            fm = painter.fontMetrics()
            text_w = fm.horizontalAdvance(self._text_buffer)
            tx, ty = self._text_pos

            # Draw text so far
            if self._text_buffer:
                painter.setPen(color)
                painter.drawText(QPointF(tx, ty), self._text_buffer)

            # Draw cursor
            if self._text_cursor_visible:
                cursor_x = tx + text_w + 2
                cursor_y_top = ty - fm.ascent()
                cursor_y_bot = ty + fm.descent()
                painter.setPen(QColor(255, 255, 255, 200))
                painter.drawLine(
                    QPointF(cursor_x, cursor_y_top),
                    QPointF(cursor_x, cursor_y_bot),
                )

        painter.end()
